// Recurring tasks (`tasks:`): the config, the registry job, the schedule,
// the run in a fake container (timeout, lock, masked output, history), the
// failure notification, and `task run|sync --plan` through the command
// line. A fake compose.sh stands in for Docker; nothing reaches a server.
@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/podship.dart';
import 'package:podship/src/ops/task_ops.dart';
import 'package:podship/src/scheduler/agent.dart';
import 'package:podship/src/scheduler/scheduler.dart';
import 'package:podship/src/server/registry.dart';
import 'package:test/test.dart';

String yamlFor({
  String host = 'studio',
  String dir = '/srv/shop',
  String home = '/srv/podship',
  String? remotePath,
  String tasks = '',
}) =>
    '''
project: shop
environments:
  production:
    host: $host
    dir: $dir
    podship_home: $home
${remotePath == null ? '' : '    remote_path: $remotePath\n'}    compose_project: shop
    health: {url: "http://127.0.0.1:8080/health"}
    plain_env: [SHOP_RUN_MODE]
    secrets: {env_file: .env, passwords_file: config/passwords.yaml}
    scheduled:
      - {name: shots, run: [dart, run, shots]}
    tasks:
$tasks
''';

const demoReset = '''
      - name: demo-reset
        command: [./bin/tool, demo, reset]
        schedule: daily 04:30
        timeout: 600
''';

EnvConfig envOf(String yaml) => PodshipConfig.parse(yaml).env('production');

/// Answers what a remote host would and records every script.
class RecordingSsh extends Ssh {
  RecordingSsh([this.registry = '']);
  final String registry;
  final scripts = <String>[];

  String _answer(String script) {
    scripts.add(script);
    if (script.contains('registry.yaml') && script.startsWith('set -euo')) {
      if (script.contains("cat '") && !script.contains('.lock')) {
        return registry;
      }
    }
    return '';
  }

  @override
  Future<String> capture(
    String host,
    String script, {
    List<int>? stdin,
  }) async => _answer(script);

  @override
  Future<({int exitCode, String stdout, String stderr})> captureResult(
    String host,
    String script, {
    List<int>? stdin,
  }) async => (exitCode: 0, stdout: _answer(script), stderr: '');

  @override
  Future<int> lines(
    String host,
    String script,
    void Function(String line, bool stderr) onLine,
  ) async {
    _answer(script);
    return 0;
  }
}

void main() {
  group('config', () {
    test('tasks parse with their schedule, timeout and service', () {
      final e = envOf(
        yamlFor(
          tasks:
              '''
$demoReset
      - name: nightly-report
        command: [./bin/tool, report]
      - name: placeholder
        enabled: false
        service: worker
''',
        ),
      );
      expect(e.tasks.map((t) => t.name), [
        'demo-reset',
        'nightly-report',
        'placeholder',
      ]);
      final d = e.tasks.first;
      expect(d.at, '04:30');
      expect(d.schedule, 'daily 04:30');
      expect(d.timeout, 600);
      expect(d.enabled, isTrue);
      expect(e.tasks[1].at, isNull);
      expect(e.tasks[1].schedule, 'nightly');
      expect(e.tasks[1].timeout, EnvTask.defaultTimeout);
      expect(e.tasks[2].enabled, isFalse);
      expect(e.tasks[2].command, isEmpty);
      expect(e.tasks[2].service, 'worker');
    });

    test('schedules are nightly, daily HH:MM or HH:MM', () {
      expect(EnvTask.parseSchedule('nightly', 'x'), isNull);
      expect(EnvTask.parseSchedule('daily 3:05', 'x'), '03:05');
      expect(EnvTask.parseSchedule('23:59', 'x'), '23:59');
      for (final bad in ['daily 24:00', 'hourly', '0 3 * * *', 'daily 3']) {
        expect(
          () => EnvTask.parseSchedule(bad, 'x'),
          throwsA(isA<ConfigException>()),
          reason: bad,
        );
      }
    });

    test('bad tasks are refused', () {
      void bad(String tasks, String message) => expect(
        () => envOf(yamlFor(tasks: tasks)),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      bad('      - {name: a}', 'needs a command');
      bad('      - {name: a, command: "./bin/tool demo reset"}', 'argv');
      bad(
        '      - {name: a, command: [x]}\n      - {name: a, command: [y]}',
        'two tasks',
      );
      bad('      - {name: shots, command: [x]}', 'two tasks');
      bad('      - {name: a, command: [x], timeout: 0}', 'timeout');
      bad(
        '      - {name: a, command: [x], schedule: "*/5 * * * *"}',
        'not a schedule',
      );
      bad('      - {name: "a b", command: [x]}', 'not a task name');
    });
  });

  group('registry job', () {
    test('runs argv in a one-off container of the current release', () {
      final e = envOf(yamlFor(tasks: demoReset));
      final job = taskJob('shop', e, e.tasks.first);
      expect(job.id, 'command:shop/production/demo-reset');
      expect(job.kind, JobKind.command, reason: 'older agents read it');
      expect(job.run, [
        '/srv/shop/current/.podship/compose.sh',
        'run',
        '--rm',
        '--no-deps',
        '-T',
        '--name',
        'shop-task-demo-reset',
        '--entrypoint',
        './bin/tool',
        'server',
        'demo',
        'reset',
      ]);
      expect(job.cwd, '/srv/shop/current');
      expect(job.at, '04:30');
      expect(job.timeout, 600);
      expect(job.task, isTrue);
      expect(job.redact, ['/srv/shop/.env', '/srv/shop/config/passwords.yaml']);
      expect(job.plain, ['SHOP_RUN_MODE']);
      // Round trip through the registry file.
      final reg = Registry()..putJob(job);
      final back = Registry.parse(reg.render()).jobs[job.id]!;
      expect(back.toMap(), job.toMap());
    });

    test('a disabled placeholder has no run and is never due', () {
      final e = envOf(
        yamlFor(tasks: '      - {name: demo-reset, enabled: false}'),
      );
      final job = taskJob('shop', e, e.tasks.first);
      expect(job.run, isNull);
      expect(job.enabled, isFalse);
      final reg = Registry()..putJob(job);
      expect(dueJobs(reg, SchedulerState(), DateTime(2026, 10, 9, 5)), isEmpty);
    });

    test('sync rewrites the commands and tasks of the environment only', () {
      final e = envOf(yamlFor(tasks: demoReset));
      final reg = Registry()
        ..putJob(
          ScheduledJob(
            kind: JobKind.command,
            project: 'shop',
            env: 'production',
            name: 'removed',
            run: ['x'],
            task: true,
          ),
        )
        ..putJob(
          ScheduledJob(
            kind: JobKind.command,
            project: 'other',
            env: 'production',
            name: 'keep',
            run: ['y'],
          ),
        );
      syncCommandJobs(reg, 'shop', e);
      expect(reg.jobs.keys.toList()..sort(), [
        'command:other/production/keep',
        'command:shop/production/demo-reset',
        'command:shop/production/shots',
      ]);
    });
  });

  group('schedule', () {
    ScheduledJob task({String? at, bool enabled = true}) => ScheduledJob(
      kind: JobKind.command,
      project: 'shop',
      env: 'production',
      name: 'demo-reset',
      run: ['x'],
      at: at,
      task: true,
      enabled: enabled,
    );

    test('a task runs once a day at or after its own time', () {
      final reg = Registry()..putJob(task(at: '04:30'));
      final st = SchedulerState()
        ..jobs[task().id] = JobState(lastRunDate: '2026-10-08');
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 3, 0)), isEmpty);
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 4, 29)), isEmpty);
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 4, 30)), hasLength(1));
      st.jobs[task().id]!.lastRunDate = '2026-10-09';
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 23, 0)), isEmpty);
    });

    test('nightly is the machine\'s time', () {
      final reg = Registry(scheduler: SchedulerSettings(at: '02:00'))
        ..putJob(task());
      final st = SchedulerState()
        ..jobs[task().id] = JobState(lastRunDate: '2026-10-08');
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 1, 59)), isEmpty);
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 2, 0)), hasLength(1));
    });

    test('a new task never fires at the tick that finds it', () {
      final reg = Registry()..putJob(task(at: '04:30'));
      final st = SchedulerState();
      // A deploy in the afternoon adds it: the first run is tomorrow.
      expect(settleNewTasks(reg, st, DateTime(2026, 10, 9, 15)), [task().id]);
      expect(dueJobs(reg, st, DateTime(2026, 10, 9, 15)), isEmpty);
      expect(dueJobs(reg, st, DateTime(2026, 10, 10, 4, 30)), hasLength(1));
      // Added at night before its time: it runs tonight.
      final early = SchedulerState();
      expect(settleNewTasks(reg, early, DateTime(2026, 10, 9, 1)), isEmpty);
      expect(dueJobs(reg, early, DateTime(2026, 10, 9, 4, 30)), hasLength(1));
    });

    test('next run', () {
      final j = task(at: '04:30');
      final n = SchedulerSettings();
      final now = DateTime(2026, 10, 9, 15);
      expect(
        nextRun(j, n, JobState(lastRunDate: '2026-10-09'), now),
        DateTime(2026, 10, 10, 4, 30),
      );
      expect(
        nextRun(
          j,
          n,
          JobState(lastRunDate: '2026-10-09'),
          DateTime(2026, 10, 9, 1),
        ),
        DateTime(2026, 10, 10, 4, 30),
      );
      expect(
        nextRun(
          j,
          n,
          JobState(lastRunDate: '2026-10-08'),
          DateTime(2026, 10, 9, 1),
        ),
        DateTime(2026, 10, 9, 4, 30),
      );
      expect(nextRun(j, n, null, now), DateTime(2026, 10, 10, 4, 30));
      expect(nextRun(task(enabled: false), n, null, now), isNull);
    });

    test('the agent also fires at the task times', () {
      final reg = Registry()
        ..putJob(task(at: '04:30'))
        ..putJob(task(at: '03:00')); // same id: replaced, nightly time
      expect(taskTimes(reg), isEmpty);
      reg.putJob(task(at: '04:30'));
      expect(taskTimes(reg), ['04:30']);
      final plist = schedulerPlist(
        home: '/srv/podship',
        settings: SchedulerSettings(),
        path: '/usr/bin',
        extraTimes: taskTimes(reg),
      );
      expect(plist, contains('<array>'));
      expect(
        plist,
        contains(
          '<dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>30</integer></dict>',
        ),
      );
      // No task times: the plist is the one older installs wrote.
      expect(
        schedulerPlist(
          home: '/srv/podship',
          settings: SchedulerSettings(),
          path: '/usr/bin',
        ),
        isNot(contains('<array>\n    <dict>')),
      );
      final units = schedulerSystemd(
        home: '/srv/podship',
        settings: SchedulerSettings(),
        path: '/usr/bin',
        extraTimes: ['04:30'],
      );
      expect(
        units.timer,
        contains('OnCalendar=*-*-* 03:00:00\nOnCalendar=*-*-* 04:30:00'),
      );
      final st = parseStatus(
        'OS Darwin\nAGENT loaded\nAGENT-AT 3:0\nAGENT-AT 4:30\n',
        host: 'h',
        home: '/h',
      );
      expect(st.agentAt, '03:00');
      expect(st.agentTimes, ['03:00', '04:30']);
    });
  });

  group('run', () {
    late Directory root;
    late String home;
    late String envDir;
    late File marks;
    late EnvConfig env;
    late List<String> removed;

    void writeCompose(String body) {
      final f = File(p.join(envDir, 'releases', 'r1', '.podship', 'compose.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/bash\n$body\n');
      Process.runSync('chmod', ['755', f.path]);
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('podship-task-');
      home = p.join(root.path, 'podship');
      envDir = p.join(root.path, 'shop');
      marks = File(p.join(root.path, 'marks'));
      Directory(p.join(envDir, 'releases', 'r1')).createSync(recursive: true);
      Link(p.join(envDir, 'current')).createSync('releases/r1');
      File(p.join(envDir, '.env')).writeAsStringSync(
        'SHOP_RUN_MODE=production-mode\nSHOP_KEY=s3cr3t-value-123\nSHORT=abc\n',
      );
      File(p.join(envDir, 'config', 'passwords.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('production:\n  database: db-password-xyz\n');
      writeCompose(
        'echo "\$@" >> ${marks.path}\n'
        'echo "key is s3cr3t-value-123, db db-password-xyz, mode production-mode"',
      );
      env = envOf(
        yamlFor(host: 'local', dir: envDir, home: home, tasks: demoReset),
      );
      removed = [];
    });
    tearDown(() => root.deleteSync(recursive: true));

    JobRunner runner({
      DateTime Function()? clock,
      Future<void> Function(JobRun)? onFailure,
    }) => JobRunner(
      home,
      clock: clock,
      onFailure: onFailure,
      removeContainer: (job, name) async => removed.add(name),
    );

    test('runs in the current release, masks secrets, records the run', () async {
      final job = taskJob('shop', env, env.tasks.first);
      final run = await runner().runJob(job, actor: 'me@example.com');
      expect(run.ok, isTrue, reason: run.error);
      expect(run.release, 'r1');
      expect(
        marks.readAsStringSync().trim(),
        'run --rm --no-deps -T --name shop-task-demo-reset --entrypoint ./bin/tool server demo reset',
      );
      // A container left by a killed run is removed first.
      expect(removed, ['shop-task-demo-reset']);
      final log = File(job.log!).readAsStringSync();
      expect(log, contains('key is ***, db ***, mode production-mode'));
      expect(log, isNot(contains('s3cr3t')));
      final dir = Directory(p.join(home, 'history', 'shop', 'production'));
      final json = dir.listSync().firstWhere((f) => f.path.endsWith('.json'));
      final rec = jsonDecode(File(json.path).readAsStringSync()) as Map;
      expect(rec['operation'], 'task demo-reset');
      expect(rec['ok'], isTrue);
      expect(rec['release'], 'r1');
      expect(rec['actor'], 'me@example.com');
      expect((rec['data'] as Map)['task'], 'demo-reset');
      final hlog = dir.listSync().firstWhere((f) => f.path.endsWith('.log'));
      expect(
        File(hlog.path).readAsStringSync(),
        isNot(contains('db-password')),
      );
      final st = SchedulerState.load(home).jobs[job.id]!;
      expect(st.lastOk, isTrue);
    });

    test(
      'a run past its timeout is stopped, its container removed, and it fails',
      () async {
        writeCompose('sleep 30');
        final e = envOf(
          yamlFor(
            host: 'local',
            dir: envDir,
            home: home,
            tasks: '      - {name: slow, command: [./bin/tool], timeout: 1}',
          ),
        );
        final watch = Stopwatch()..start();
        final run = await runner().runJob(taskJob('shop', e, e.tasks.first));
        expect(watch.elapsed.inSeconds, lessThan(15));
        expect(run.ok, isFalse);
        expect(run.error, 'timeout after 1s');
        expect(removed, ['shop-task-slow', 'shop-task-slow']);
        expect(
          SchedulerState.load(home).jobs[run.job.id]!.lastError,
          'timeout after 1s',
        );
      },
    );

    test('a task already running is not started twice', () async {
      final job = taskJob('shop', env, env.tasks.first);
      final lockPath = p.join(
        home,
        'scheduler',
        'locks',
        '${job.id.replaceAll('/', '_')}.lock',
      );
      File(lockPath).createSync(recursive: true);
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
      final run = await runner().runJob(job);
      holder.kill();
      expect(run.skipped, isTrue);
      expect(marks.existsSync(), isFalse);
    });

    test('a scheduled failure is reported once; the tick goes on', () async {
      writeCompose('echo "boom s3cr3t-value-123" >&2; exit 4');
      final reg = Registry()..putJob(taskJob('shop', env, env.tasks.first));
      File(p.join(home, 'registry.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(reg.render());
      final failed = <JobRun>[];
      var now = DateTime(2026, 10, 9, 15);
      final s = runner(clock: () => now, onFailure: (r) async => failed.add(r));
      expect(await s.tick(), isEmpty); // first tick: seeds
      now = DateTime(2026, 10, 10, 4, 30);
      final runs = await s.tick();
      expect(runs, hasLength(1));
      expect(runs.single.ok, isFalse);
      expect(runs.single.error, 'exit code 4');
      expect(failed.map((r) => r.job.id), [
        'command:shop/production/demo-reset',
      ]);
      final log = File(
        p.join(home, 'log', 'task-shop-production-demo-reset.log'),
      );
      expect(log.readAsStringSync(), contains('boom ***'));
      // The notification the agent sends.
      final n = Notification.schedulerJobFailed(
        job: failed.single.job.id,
        error: failed.single.error!,
      );
      expect(n.event.id, 'scheduler_job_failed');
    });
  });

  group('command line', () {
    late Directory root;
    late File marks;

    setUp(() {
      root = Directory.systemTemp.createTempSync('podship-task-cli-');
      marks = File(p.join(root.path, 'marks'));
      final envDir = p.join(root.path, 'shop');
      final c = File(p.join(envDir, 'releases', 'r1', '.podship', 'compose.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/bash\necho "\$@" >> ${marks.path}\n');
      Process.runSync('chmod', ['755', c.path]);
      Link(p.join(envDir, 'current')).createSync('releases/r1');
      // A fake docker first in the PATH: the run removes a stale container.
      final bin = Directory(p.join(root.path, 'bin'))..createSync();
      final docker = File(
        p.join(bin.path, 'docker'),
      )..writeAsStringSync('#!/bin/bash\necho "docker \$@" >> ${marks.path}\n');
      Process.runSync('chmod', ['755', docker.path]);
      File(p.join(root.path, 'podship.yaml')).writeAsStringSync(
        yamlFor(
          host: 'local',
          dir: envDir,
          home: p.join(root.path, 'podship'),
          remotePath: bin.path,
          tasks: demoReset,
        ),
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<int?> run(List<String> args, [Ssh? ssh]) => PodshipRunner(
      ssh: ssh ?? RecordingSsh(),
    ).run(['-C', root.path, '--no-notify', ...args]);

    for (final flag in ['--plan', '--dry-run']) {
      test('task run $flag runs nothing', () async {
        final code = await run([
          'task',
          'run',
          'demo-reset',
          '--env',
          'production',
          flag,
        ]);
        expect(code, 0);
        expect(marks.existsSync(), isFalse);
        expect(
          Directory(p.join(root.path, 'podship', 'history')).existsSync(),
          isFalse,
        );
      });
    }

    test('task run runs it (the fake is reachable)', () async {
      final code = await run([
        'task',
        'run',
        'demo-reset',
        '--env',
        'production',
      ]);
      expect(code, 0);
      expect(
        marks.readAsStringSync(),
        contains('--entrypoint ./bin/tool server demo reset'),
      );
      expect(
        marks.readAsStringSync(),
        contains('docker rm -f shop-task-demo-reset'),
      );
    });

    test('task run of an unknown task fails', () async {
      final code = await run(['task', 'run', 'nope', '--env', 'production']);
      expect(code, isNot(0));
    });

    test('task sync --plan writes no registry; without it, it does', () async {
      File(
        p.join(root.path, 'podship.yaml'),
      ).writeAsStringSync(yamlFor(tasks: demoReset));
      bool writesRegistry(RecordingSsh s) =>
          s.scripts.any((x) => x.contains('registry.yaml.lock'));
      final planned = RecordingSsh();
      expect(
        await run(['task', 'sync', '--env', 'production', '--plan'], planned),
        0,
      );
      expect(writesRegistry(planned), isFalse);
      final applied = RecordingSsh();
      await run(['task', 'sync', '--env', 'production'], applied);
      expect(writesRegistry(applied), isTrue);
    });
  });

  test('a failed manual task run notifies scheduler_job_failed', () {
    final w = OperationWatcher();
    w.onEvent(OperationStarted('task run', project: 'shop', env: 'production'));
    final ns = w.onEvent(
      OperationFinished(
        OperationResult(
          operation: 'task run',
          ok: false,
          duration: const Duration(seconds: 3),
          project: 'shop',
          env: 'production',
          error: 'task demo-reset failed: exit code 4',
          data: {'job': 'command:shop/production/demo-reset'},
        ),
      ),
    );
    expect(ns.single.event.id, 'scheduler_job_failed');
    expect(ns.single.title, contains('command:shop/production/demo-reset'));
  });

  test('task rows show the last and the next run', () {
    final e = envOf(yamlFor(tasks: demoReset));
    final reg = Registry()..putJob(taskJob('shop', e, e.tasks.first));
    final rows = taskRows(
      'shop',
      e,
      reg,
      {
        'jobs': {
          'command:shop/production/demo-reset': {
            'last_run': '2026-10-09T10:30:00Z',
            'last_run_date': '2026-10-09',
            'last_ok': true,
            'last_duration_s': 12,
          },
        },
      },
      DateTime(2026, 10, 9, 15),
      agentTimes: ['03:00'],
      watched: false,
    );
    final r = rows.single;
    expect(r['synced'], isTrue);
    expect(r['next_run'], '2026-10-10 04:30');
    expect(r['warning'], contains('scheduler install'));
    expect(formatTaskRow(r), contains('last: 2026-10-09T10:30:00Z ok in 12s'));
    final missing = taskRows(
      'shop',
      e,
      Registry(),
      const {},
      DateTime(2026, 10, 9),
    );
    expect(formatTaskRow(missing.single), contains('not on the server yet'));
  });
}
