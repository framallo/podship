import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/scheduler/agent.dart';
import 'package:podship/src/scheduler/scheduler.dart';
import 'package:podship/src/server/registry.dart';
import 'package:test/test.dart';

ScheduledJob backup(String project, String env, {String? conf}) => ScheduledJob(
  kind: JobKind.backup,
  project: project,
  env: env,
  script: '/srv/podship/lib/backup.sh',
  conf: conf ?? '/srv/podship/etc/$project-backup.conf',
  log: '/srv/podship/log/$project-backup.log',
  path: '/usr/bin:/bin',
);

ScheduledJob pull(String project, String env) => ScheduledJob(
  kind: JobKind.pull,
  project: project,
  env: env,
  projectDir: '/work/$project',
);

void main() {
  group('registry', () {
    test('renders and parses jobs and the run time', () {
      final r = Registry(scheduler: SchedulerSettings(at: '04:15'))
        ..putJob(pull('caza', 'production'))
        ..putJob(backup('boceto', 'production'));
      final back = Registry.parse(r.render());
      expect(back.scheduler.at, '04:15');
      expect(back.scheduler.hour, 4);
      expect(back.scheduler.minute, 15);
      expect(back.jobs.keys, [
        'backup:boceto/production',
        'pull:caza/production',
      ]);
      final b = back.jobs['backup:boceto/production']!;
      expect(b.conf, '/srv/podship/etc/boceto-backup.conf');
      expect(b.path, '/usr/bin:/bin');
      expect(back.jobs['pull:caza/production']!.projectDir, '/work/caza');
      // A registry without the new sections still parses.
      final old = Registry.parse(
        'version: 1\nport_range: [20000, 20999]\nentries:\n  {}\n',
      );
      expect(old.jobs, isEmpty);
      expect(old.scheduler.at, '03:00');
    });

    test('run order is backups, then pulls', () {
      final r = Registry()
        ..putJob(pull('a', 'production'))
        ..putJob(backup('z', 'staging'))
        ..putJob(backup('b', 'production'));
      expect(r.orderedJobs.map((j) => j.id), [
        'backup:b/production',
        'backup:z/staging',
        'pull:a/production',
      ]);
      expect(r.jobsOf('z', 'staging').single.id, 'backup:z/staging');
    });

    test('removing an entry removes its jobs', () {
      final r = Registry()
        ..put(
          RegistryEntry(
            project: 'a',
            env: 'production',
            dir: '/srv/a',
            composeProject: 'a',
          ),
        )
        ..putJob(backup('a', 'production'))
        ..putJob(pull('a', 'production'))
        ..putJob(backup('b', 'production'));
      r.remove('a/production');
      expect(r.jobs.keys, ['backup:b/production']);
    });

    test('run times are HH:MM', () {
      expect(SchedulerSettings.validTime('3:05'), '03:05');
      expect(SchedulerSettings.validTime('23:59'), '23:59');
      expect(
        () => SchedulerSettings.validTime('24:00'),
        throwsA(isA<RegistryConflict>()),
      );
      expect(
        () => SchedulerSettings.validTime('tonight'),
        throwsA(isA<RegistryConflict>()),
      );
    });
  });

  group('due computation', () {
    final reg = Registry()
      ..putJob(pull('a', 'production'))
      ..putJob(backup('a', 'production'))
      ..putJob(backup('b', 'production'));

    test('a job runs once per local date, backups first', () {
      final st = SchedulerState();
      final night = DateTime(2026, 10, 8, 3, 0);
      expect(dueJobs(reg, st, night).map((j) => j.id), [
        'backup:a/production',
        'backup:b/production',
        'pull:a/production',
      ]);
      for (final j in reg.jobs.values) {
        st.jobs[j.id] = JobState(lastRunDate: localDate(night));
      }
      // The run at load after a reboot the same day: nothing to do.
      expect(dueJobs(reg, st, DateTime(2026, 10, 8, 17, 42)), isEmpty);
      // Next night: everything again.
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 3, 0)), hasLength(3));
    });

    test('a missed night after sleep is caught up once, never a burst', () {
      final st = SchedulerState();
      for (final j in reg.jobs.values) {
        st.jobs[j.id] = JobState(lastRunDate: '2026-10-01');
      }
      // The machine slept from Oct 1 to Oct 5 and wakes at 11:20.
      final wake = DateTime(2026, 10, 5, 11, 20);
      final due = dueJobs(reg, st, wake);
      expect(due, hasLength(3));
      for (final j in due) {
        st.jobs[j.id] = JobState(lastRunDate: localDate(wake));
      }
      // A second run the same day (the calendar fire never came, launchd
      // runs the missed one on wake) does nothing.
      expect(dueJobs(reg, st, DateTime(2026, 10, 5, 11, 21)), isEmpty);
      expect(dueJobs(reg, st, DateTime(2026, 10, 5, 23, 59)), isEmpty);
      expect(dueJobs(reg, st, DateTime(2026, 10, 6, 3, 0)), hasLength(3));
    });

    test('a DST change does not skip or double a night', () {
      // Wall clock dates decide, not instants: the night the clocks move
      // (23 h or 25 h long) still gives exactly one run.
      final st = SchedulerState();
      final r = Registry()..putJob(backup('a', 'production'));
      // Instants of 03:00 wall clock in a zone that goes UTC-6 → UTC-5 on
      // Mar 8 and back on Nov 1 (what launchd fires with).
      final fires = [
        DateTime.utc(2026, 3, 7, 9, 0), // Mar 7 03:00 at UTC-6
        DateTime.utc(2026, 3, 8, 8, 0), // Mar 8 03:00 at UTC-5 (23 h later)
        DateTime.utc(2026, 3, 9, 8, 0),
        DateTime.utc(2026, 11, 1, 9, 0), // Nov 1 03:00 at UTC-6 (25 h night)
        DateTime.utc(2026, 11, 2, 9, 0),
      ];
      final offsets = [-6, -5, -5, -6, -6];
      var runs = 0;
      for (final (i, f) in fires.indexed) {
        final wall = f.add(Duration(hours: offsets[i]));
        final due = dueJobs(r, st, wall);
        runs += due.length;
        for (final j in due) {
          st.jobs[j.id] = JobState(lastRunDate: localDate(wall));
        }
        // The spring-forward day: a second fire the same wall-clock day
        // (RunAtLoad after a reboot at 20:00) runs nothing.
        expect(
          dueJobs(r, st, wall.add(const Duration(hours: 17))),
          isEmpty,
          reason: 'fire $i',
        );
      }
      expect(runs, 5);
    });

    test('disabled jobs are never due', () {
      final r = Registry()
        ..putJob(
          ScheduledJob(
            kind: JobKind.backup,
            project: 'a',
            env: 'production',
            enabled: false,
            conf: '/x.conf',
          ),
        );
      expect(dueJobs(r, SchedulerState(), DateTime(2026, 10, 8, 3)), isEmpty);
    });
  });

  group('tick', () {
    late Directory home;
    late File marks;
    late Registry reg;

    setUp(() {
      home = Directory.systemTemp.createTempSync('podship-sched-');
      marks = File(p.join(home.path, 'marks'));
      final script = File(p.join(home.path, 'lib', 'backup.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/bash\necho "[backup] stamp 2026-10-08T0300"\necho "\$1" >> ${marks.path}\n[ "\${FAIL:-}" = 1 ] && exit 3\nexit 0\n',
        );
      reg = Registry()
        ..putJob(
          ScheduledJob(
            kind: JobKind.backup,
            project: 'a',
            env: 'production',
            script: script.path,
            conf: 'conf-a',
            log: p.join(home.path, 'log', 'a.log'),
          ),
        )
        ..putJob(
          ScheduledJob(
            kind: JobKind.backup,
            project: 'b',
            env: 'production',
            script: script.path,
            conf: 'conf-b',
          ),
        );
      File(p.join(home.path, 'registry.yaml')).writeAsStringSync(reg.render());
    });

    tearDown(() => home.deleteSync(recursive: true));

    List<String> marked() =>
        marks.existsSync() ? marks.readAsLinesSync() : const [];

    test(
      'the first tick seeds and runs nothing; the next night runs each job once; a job already running is skipped',
      () async {
        var now = DateTime(2026, 10, 8, 15, 0);
        final s = JobRunner(home.path, clock: () => now);
        expect(await s.tick(), isEmpty);
        expect(marked(), isEmpty);
        var st = SchedulerState.load(home.path);
        expect(st.jobs['backup:a/production']!.lastRunDate, '2026-10-08');

        now = DateTime(2026, 10, 9, 3, 0);
        final runs = await s.tick();
        expect(runs.map((r) => r.job.id), [
          'backup:a/production',
          'backup:b/production',
        ]);
        expect(runs.every((r) => r.ok), isTrue);
        expect(runs.first.stamp, '2026-10-08T0300');
        expect(marked(), ['conf-a', 'conf-b']);
        st = SchedulerState.load(home.path);
        expect(st.jobs['backup:b/production']!.lastRunDate, '2026-10-09');
        expect(st.jobs['backup:a/production']!.lastStamp, '2026-10-08T0300');

        // Same date again (RunAtLoad after a reboot): nothing.
        now = DateTime(2026, 10, 9, 18, 0);
        expect(await s.tick(), isEmpty);
        expect(marked(), hasLength(2));

        // The job log, the scheduler log and a history record exist.
        expect(
          File(p.join(home.path, 'log', 'a.log')).readAsStringSync(),
          contains('[backup] stamp'),
        );
        final log = File(
          p.join(home.path, 'log', 'scheduler.log'),
        ).readAsStringSync();
        expect(log, contains('first run'));
        expect(log, contains('backup:a/production: ok'));
        expect(log, contains('nothing due'));
        final hist = Directory(
          p.join(home.path, 'history', 'a', 'production'),
        ).listSync().map((f) => p.basename(f.path)).toList()..sort();
        expect(hist, hasLength(2));
        expect(hist.first, endsWith('-backup-now.json'));
        final rec =
            jsonDecode(
                  File(
                    p.join(home.path, 'history', 'a', 'production', hist.first),
                  ).readAsStringSync(),
                )
                as Map;
        expect(rec['actor'], 'podship-scheduler');
        expect(rec['ok'], isTrue);
        expect((rec['data'] as Map)['stamp'], '2026-10-08T0300');

        // A lock held by another process: the job is skipped, not run twice.
        final lockPath = p.join(
          home.path,
          'scheduler',
          'locks',
          'backup:a_production.lock',
        );
        final holder = await Process.start('python3', [
          '-c',
          'import fcntl, sys, time\n'
              'f = open(sys.argv[1], "a")\n'
              'fcntl.lockf(f, fcntl.LOCK_EX)\n'
              'print("locked", flush=True)\n'
              'time.sleep(30)\n',
          lockPath,
        ]);
        await holder.stdout
            .transform(utf8.decoder)
            .firstWhere((s) => s.contains('locked'));
        final skipped = await s.runJob(reg.jobs['backup:a/production']!);
        holder.kill();
        expect(skipped.skipped, isTrue);
        expect(marked(), hasLength(2));
      },
    );

    test('a failing job does not stop the others and is recorded', () async {
      var now = DateTime(2026, 10, 8, 3, 0);
      final s = JobRunner(home.path, clock: () => now);
      await s.tick(); // seeds
      now = DateTime(2026, 10, 9, 3, 0);
      // The first job fails (its conf makes the fake script exit 3).
      final failing = Registry.parse(
        File(p.join(home.path, 'registry.yaml')).readAsStringSync(),
      );
      final a = failing.jobs['backup:a/production']!;
      failing.putJob(
        ScheduledJob(
          kind: a.kind,
          project: a.project,
          env: a.env,
          script: a.script,
          conf: a.conf,
          path: '/nonexistent',
        ),
      );
      File(
        p.join(home.path, 'registry.yaml'),
      ).writeAsStringSync(failing.render());
      final runs = await s.tick();
      expect(runs, hasLength(2));
      final st = SchedulerState.load(home.path);
      expect(st.jobs['backup:b/production']!.lastOk, isTrue);
      expect(st.jobs['backup:a/production']!.lastRunDate, '2026-10-09');
    });

    test('seed marks only jobs without state', () {
      final s = JobRunner(home.path, clock: () => DateTime(2026, 10, 8, 12));
      SchedulerState(
        jobs: {'backup:a/production': JobState(lastRunDate: '2026-10-01')},
      ).save(home.path);
      expect(s.seed(), ['backup:b/production']);
      final st = SchedulerState.load(home.path);
      expect(st.jobs['backup:a/production']!.lastRunDate, '2026-10-01');
      expect(st.jobs['backup:b/production']!.lastRunDate, '2026-10-08');
      expect(s.seed(), isEmpty);
    });
  });

  group('agent', () {
    test('the launchd plist fires nightly and at load', () {
      final plist = schedulerPlist(
        home: '/Users/me/podship',
        settings: SchedulerSettings(at: '03:00'),
        path: '/opt/homebrew/bin:/usr/bin:/bin',
      );
      expect(plist, contains('<string>$schedulerLabel</string>'));
      expect(
        plist,
        contains(
          '<string>/Users/me/podship/bin/podship</string>\n    <string>scheduler</string>\n    <string>tick</string>\n    <string>--home</string>\n    <string>/Users/me/podship</string>',
        ),
      );
      expect(
        plist,
        contains(
          '<key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer>',
        ),
      );
      expect(plist, contains('<key>RunAtLoad</key><true/>'));
      expect(plist, isNot(contains('StartInterval')));
      final u = schedulerSystemd(
        home: '/srv/podship',
        settings: SchedulerSettings(at: '04:30'),
        path: '/usr/bin:/bin',
      );
      expect(u.timer, contains('OnCalendar=*-*-* 04:30:00'));
      expect(u.timer, contains('Persistent=true'));
      expect(
        u.service,
        contains(
          'ExecStart=/srv/podship/bin/podship scheduler tick --home /srv/podship',
        ),
      );
    });

    test(
      'install is idempotent: the agent is registered once, a second install changes nothing',
      () async {
        final tmp = Directory.systemTemp.createTempSync('podship-agent-');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final home = p.join(tmp.path, 'podship');
        final stubs = Directory(p.join(tmp.path, 'stubs'))..createSync();
        final calls = File(p.join(tmp.path, 'launchctl.calls'));
        // launchctl: print succeeds when "loaded" exists; bootstrap creates
        // it; bootout removes it. Every call is logged.
        File(p.join(stubs.path, 'launchctl')).writeAsStringSync(
          '#!/bin/bash\necho "\$1" >> ${calls.path}\n'
          'case "\$1" in\n'
          '  print) [ -f ${tmp.path}/loaded ] && echo "state = running" || exit 113;;\n'
          '  bootstrap) touch ${tmp.path}/loaded;;\n'
          '  bootout) rm -f ${tmp.path}/loaded;;\n'
          'esac\n',
        );
        File(p.join(home, 'bin', 'podship'))
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/bash\necho "seed \$*"\n');
        for (final f in ['launchctl', 'bin/podship']) {
          await Process.run('chmod', [
            '755',
            f == 'launchctl' ? p.join(stubs.path, f) : p.join(home, f),
          ]);
        }
        final script = installLaunchdScript(
          home: home,
          settings: SchedulerSettings(at: '03:00'),
          path: '/usr/bin:/bin',
        );
        final env = {'HOME': tmp.path, 'PATH': '${stubs.path}:/usr/bin:/bin'};
        Future<String> run() async {
          final r = await Process.run('bash', [
            '-c',
            'set -euo pipefail\n$script',
          ], environment: env);
          expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
          return '${r.stdout}';
        }

        final first = await run();
        expect(first, contains('registered'));
        expect(first, contains('seed scheduler tick --home $home --seed'));
        expect(
          File(
            p.join(
              tmp.path,
              'Library',
              'LaunchAgents',
              '$schedulerLabel.plist',
            ),
          ).existsSync(),
          isTrue,
        );
        final second = await run();
        expect(second, contains('unchanged, still loaded'));
        final log = calls.readAsLinesSync();
        expect(log.where((c) => c == 'bootstrap'), hasLength(1));
        expect(log.where((c) => c == 'bootout'), hasLength(1));
        // A new run time changes the plist: registered again, once.
        final r3 = await Process.run('bash', [
          '-c',
          'set -euo pipefail\n${installLaunchdScript(
            home: home,
            settings: SchedulerSettings(at: '04:00'),
            path: '/usr/bin:/bin',
          )}',
        ], environment: env);
        expect('${r3.stdout}', contains('registered (nightly at 04:00'));
        expect(
          calls.readAsLinesSync().where((c) => c == 'bootstrap'),
          hasLength(2),
        );
      },
    );

    test('every agent script parses with bash', () async {
      for (final s in [
        installLaunchdScript(
          home: '/h',
          settings: SchedulerSettings(),
          path: '/bin',
        ),
        installSystemdScript(
          home: '/h',
          settings: SchedulerSettings(),
          path: '/bin',
        ),
        uninstallScript(macos: true),
        uninstallScript(macos: false),
        statusScript('/h'),
        legacyScanScript,
        retireLegacyScript(const [], replaces: ['x'], macos: true),
        retireLegacyScript(const [], replaces: ['x'], macos: false),
      ]) {
        final r = await Process.run('/bin/bash', ['-n', '-c', s]);
        expect(r.exitCode, 0, reason: '${r.stderr}\n$s');
      }
    });

    test('status output is parsed', () {
      final reg = Registry()..putJob(backup('a', 'production'));
      final st = parseStatus(
        'OS Darwin\nAGENT loaded\nAGENT-AT 3:0\nBIN podship 0.2.0\n'
        'STATE-BEGIN\n{"last_tick":"2026-10-08T09:00:00Z","jobs":{"backup:a/production":{"last_run_date":"2026-10-08","last_ok":true}}}\nSTATE-END\n'
        'REGISTRY-BEGIN\n${reg.render()}REGISTRY-END\nLOG-BEGIN\nline 1\nline 2\nLOG-END\n',
        host: 'local',
        home: '/h',
      );
      expect(st.agentLoaded, isTrue);
      expect(st.agentAt, '03:00');
      expect(st.binVersion, 'podship 0.2.0');
      expect(st.logTail, ['line 1', 'line 2']);
      final j = st.jobs.single;
      expect(j['id'], 'backup:a/production');
      expect(j['last_ok'], isTrue);
      expect(j['last_run_date'], '2026-10-08');
      expect(st.toJson()['agent'], 'loaded');
      final missing = parseStatus(
        'OS Linux\nAGENT missing\n',
        host: 'srv',
        home: '/h',
      );
      expect(missing.agentLoaded, isFalse);
      expect(missing.jobs, isEmpty);
    });
  });

  group('migration', () {
    const backupPlist =
        '{"Label":"dev.podship.backup.boceto","ProgramArguments":["/bin/bash","/Users/me/podship/lib/backup.sh","/Users/me/podship/etc/dev.podship.backup.boceto.conf"],'
        '"EnvironmentVariables":{"PATH":"/opt/homebrew/bin:/usr/bin:/bin"},"StartCalendarInterval":{"Hour":3,"Minute":30},'
        '"StandardOutPath":"/Users/me/podship/log/dev.podship.backup.boceto.log","StandardErrorPath":"/Users/me/podship/log/dev.podship.backup.boceto.log"}';
    const pullPlist =
        '{"Label":"dev.podship.pull.cazafacturas.production","ProgramArguments":["/Users/me/.pub-cache/bin/podship","backup","pull","--env","production","--yes"],'
        '"WorkingDirectory":"/Users/me/work/cazafacturas","EnvironmentVariables":{"PATH":"/Users/me/.pub-cache/bin:/opt/homebrew/bin:/usr/bin:/bin"},'
        '"StartCalendarInterval":[{"Hour":10,"Minute":0},{"Hour":16,"Minute":0},{"Hour":22,"Minute":0}],"RunAtLoad":true}';

    test('launch agents become jobs; the registry names the environment', () {
      final reg = Registry()
        ..put(
          RegistryEntry(
            project: 'boceto',
            env: 'production',
            dir: '/Users/me/services/boceto',
            composeProject: 'boceto',
            backupUnit: 'dev.podship.backup.boceto',
          ),
        );
      final units = parseLegacyUnits(
        'PLIST /Users/me/Library/LaunchAgents/dev.podship.backup.boceto.plist\n$backupPlist\nPLIST-END\n'
        'PLIST /Users/me/Library/LaunchAgents/dev.podship.pull.cazafacturas.production.plist\n$pullPlist\nPLIST-END\n'
        'PLIST /Users/me/Library/LaunchAgents/dev.podship.other.plist\n{"Label":"dev.podship.other"}\nPLIST-END\n',
        reg,
      );
      expect(units, hasLength(2));
      final b = units[0];
      expect(b.name, 'dev.podship.backup.boceto');
      expect(b.times, ['03:30']);
      expect(b.job.id, 'backup:boceto/production');
      expect(
        b.job.conf,
        '/Users/me/podship/etc/dev.podship.backup.boceto.conf',
      );
      expect(b.job.script, '/Users/me/podship/lib/backup.sh');
      expect(b.job.path, '/opt/homebrew/bin:/usr/bin:/bin');
      expect(b.job.log, '/Users/me/podship/log/dev.podship.backup.boceto.log');
      final pl = units[1];
      expect(pl.job.id, 'pull:cazafacturas/production');
      expect(pl.times, ['10:00', '16:00', '22:00']);
      expect(pl.job.projectDir, '/Users/me/work/cazafacturas');
      expect(
        pl.job.note,
        contains('migrated from dev.podship.pull.cazafacturas.production'),
      );
      // Without a registry entry, the plist comment names the environment.
      final noReg = parseLegacyUnits(
        'PLIST /x/dev.podship.backup.boceto.plist\n${backupPlist.replaceFirst('{', '{"comment":"Written by podship: daily backup of boceto/production.",')}\nPLIST-END\n',
        Registry(),
      );
      expect(noReg.single.job.id, 'backup:boceto/production');
      // Retirement: boot out and rename, never delete.
      final retire = retireLegacyScript(units, macos: true);
      expect(
        retire,
        contains('launchctl bootout gui/\$(id -u)/dev.podship.backup.boceto'),
      );
      expect(
        retire,
        contains(
          '/Users/me/Library/LaunchAgents/dev.podship.backup.boceto.plist.migrated-by-podship',
        ),
      );
      expect(retire, isNot(contains('rm ')));
    });

    test('systemd timers become backup jobs', () {
      final reg = Registry()
        ..put(
          RegistryEntry(
            project: 'cazafacturas',
            env: 'vps',
            dir: '/srv/caza',
            composeProject: 'cazafacturas',
            backupUnit: 'podship-backup-cazafacturas',
          ),
        );
      final units = parseLegacyUnits(
        'TIMER /etc/systemd/system/podship-backup-cazafacturas.timer\n'
        '# Written by podship.\n[Timer]\nOnCalendar=*-*-* 03:30:00 America/Mexico_City\nPersistent=true\n'
        'SERVICE\n# Written by podship: backup of cazafacturas/vps.\n[Service]\nType=oneshot\n'
        'ExecStart=/srv/podship/lib/backup.sh /srv/podship/etc/podship-backup-cazafacturas.conf\n'
        'TIMER-END\n',
        reg,
      );
      final u = units.single;
      expect(u.job.id, 'backup:cazafacturas/vps');
      expect(u.times, ['03:30 America/Mexico_City']);
      expect(u.job.conf, '/srv/podship/etc/podship-backup-cazafacturas.conf');
      final retire = retireLegacyScript(units, macos: false);
      expect(
        retire,
        contains('systemctl disable --now podship-backup-cazafacturas.timer'),
      );
      expect(retire, contains('.migrated-by-podship'));
      expect(retire, contains('systemctl daemon-reload'));
    });

    test('an imported job never overrides one written by backup schedule', () {
      final reg = Registry()
        ..putJob(backup('boceto', 'production', conf: '/new.conf'));
      final units = parseLegacyUnits(
        'PLIST /x/dev.podship.backup.boceto.plist\n${backupPlist.replaceFirst('{', '{"comment":"backup of boceto/production",')}\nPLIST-END\n',
        reg,
      );
      for (final u in units) {
        reg.jobs.putIfAbsent(u.job.id, () => u.job);
      }
      expect(reg.jobs['backup:boceto/production']!.conf, '/new.conf');
    });
  });
}
