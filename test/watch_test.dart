@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/config/config.dart';
import 'package:podship/src/notify/notify.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/watch_ops.dart';
import 'package:podship/src/scheduler/agent.dart';
import 'package:podship/src/scheduler/scheduler.dart';
import 'package:podship/src/server/registry.dart';
import 'package:podship/src/watch/heal.dart';
import 'package:podship/src/watch/incident.dart';
import 'package:podship/src/watch/model.dart';
import 'package:podship/src/watch/runner.dart';
import 'package:test/test.dart';

const key = 'shop/production';
final t0 = DateTime.utc(2026, 10, 8, 15, 26);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

const rules = IncidentRules(
  alertAfter: 2,
  healAttempts: 2,
  healBackoff: Duration(minutes: 6),
);

Decision fail(TargetState s, int min, {bool canHeal = true}) => step(
  s,
  Outcome.fail,
  at(min),
  key: key,
  canHeal: canHeal,
  rules: rules,
  problem: 'status 502',
);

Decision pass(TargetState s, int min, {bool canHeal = true}) =>
    step(s, Outcome.pass, at(min), key: key, canHeal: canHeal, rules: rules);

WatchTarget target({
  String project = 'shop',
  String env = 'production',
  bool owner = true,
  bool heal = true,
}) => WatchTarget(
  project: project,
  env: env,
  checks: [WatchCheck(url: 'https://$env.$project.example/health')],
  owner: owner,
  machine: 'box',
  heal: heal,
  localUrls: owner ? ['http://127.0.0.1:20001/health'] : const [],
  releaseDir: owner ? '/srv/$project/current' : null,
);

void main() {
  group('incident state machine', () {
    test('one failure is silent; it passes again without a message', () {
      final s = TargetState();
      expect(fail(s, 0).isNothing, isTrue);
      expect(s.fails, 1);
      expect(s.isDown, isFalse);
      expect(pass(s, 2).isNothing, isTrue);
      expect(s.fails, 0);
      expect(s.firstFail, isNull);
    });

    test('two failures in a row: one alert and heal attempt 1', () {
      final s = TargetState();
      fail(s, 0);
      final d = fail(s, 2);
      expect(d.alertDown, isTrue);
      expect(d.heal, isTrue);
      expect(d.healAttempt, 1);
      expect(d.incident, '20261008T152600Z-$key');
      expect(s.isDown, isTrue);
    });

    test('later failures never alert again; heal 2 waits for the backoff; '
        'then one "still down"', () {
      final s = TargetState();
      fail(s, 0);
      fail(s, 2); // alert + heal 1 at minute 2
      final d4 = fail(s, 4);
      expect(d4.alertDown, isFalse);
      expect(d4.heal, isFalse, reason: 'backoff: 6 min after heal 1');
      expect(d4.alertStillDown, isFalse);
      final d8 = fail(s, 8);
      expect(d8.heal, isTrue);
      expect(d8.healAttempt, 2);
      expect(fail(s, 10).isNothing, isTrue);
      expect(fail(s, 12).isNothing, isTrue);
      final d14 = fail(s, 14);
      expect(d14.alertStillDown, isTrue, reason: '6 min after the last heal');
      expect(d14.heal, isFalse);
      for (var m = 16; m < 300; m += 2) {
        final d = fail(s, m);
        expect(d.isNothing, isTrue, reason: 'minute $m');
      }
      expect(s.heals, 2);
    });

    test('recovery: one message with the downtime from the first failure', () {
      final s = TargetState();
      fail(s, 0);
      fail(s, 2);
      fail(s, 4);
      final d = pass(s, 6);
      expect(d.alertRecovered, isTrue);
      expect(d.downtime, const Duration(minutes: 6));
      expect(d.incident, '20261008T152600Z-$key');
      expect(s.isDown, isFalse);
      expect(s.heals, 0);
      expect(pass(s, 8).isNothing, isTrue, reason: 'only once');
    });

    test('a flap after recovery opens a new incident with fresh heals', () {
      final s = TargetState();
      fail(s, 0);
      fail(s, 2);
      pass(s, 4);
      fail(s, 6);
      final d = fail(s, 8);
      expect(d.alertDown, isTrue);
      expect(d.healAttempt, 1);
      expect(d.incident, '20261008T153200Z-$key');
    });

    test('a cross-watch target alerts and recovers but never heals', () {
      final s = TargetState();
      fail(s, 0, canHeal: false);
      final d = fail(s, 2, canHeal: false);
      expect(d.alertDown, isTrue);
      expect(d.heal, isFalse);
      for (var m = 4; m < 60; m += 2) {
        expect(fail(s, m, canHeal: false).isNothing, isTrue);
      }
      expect(pass(s, 60, canHeal: false).alertRecovered, isTrue);
    });

    test(
      'a cross-watch copy with a live owner stays silent; it alerts once the owner is dead',
      () {
        final s = TargetState();
        Decision f(int m, {required bool mayAlert}) => step(
          s,
          Outcome.fail,
          at(m),
          key: key,
          canHeal: false,
          rules: rules,
          mayAlert: mayAlert,
        );
        f(0, mayAlert: false);
        expect(f(2, mayAlert: false).isNothing, isTrue);
        expect(f(4, mayAlert: false).isNothing, isTrue);
        expect(s.isDown, isFalse);
        final d = f(6, mayAlert: true);
        expect(d.alertDown, isTrue);
        expect(
          d.incident,
          '20261008T152600Z-$key',
          reason: 'from the first failure',
        );
        expect(f(8, mayAlert: false).isNothing, isTrue);
        expect(
          pass(s, 10, canHeal: false).downtime,
          const Duration(minutes: 10),
        );
      },
    );

    test('a cross-watch copy that never alerted recovers silently', () {
      final s = TargetState();
      for (var m = 0; m < 10; m += 2) {
        step(s, Outcome.fail, at(m), key: key, canHeal: false, mayAlert: false);
      }
      expect(pass(s, 10, canHeal: false).isNothing, isTrue);
    });

    test('an unknown run (no internet here) changes nothing', () {
      final s = TargetState();
      fail(s, 0);
      final d = step(s, Outcome.unknown, at(2), key: key, canHeal: true);
      expect(d.isNothing, isTrue);
      expect(s.fails, 1);
      expect(fail(s, 4).alertDown, isTrue);
    });

    test('the state survives JSON', () {
      final s = TargetState();
      fail(s, 0);
      fail(s, 2);
      final back = WatchState.fromJson(
        jsonDecode(jsonEncode(WatchState(targets: {key: s}).toJson())) as Map,
      ).targets[key]!;
      expect(back.fails, 2);
      expect(back.incident, s.incident);
      expect(back.heals, 1);
      expect(back.firstFail, at(0));
      expect(pass(back, 4).downtime, const Duration(minutes: 4));
    });
  });

  group('heal rules', () {
    final now = DateTime.utc(2026, 10, 9, 17, 0);
    test('heartbeat: fresh, stale, busy healing, out of reach', () {
      Map<String, Object?> hb(int ageS, {int? busyInS}) => {
        'time': now.subtract(Duration(seconds: ageS)).toIso8601String(),
        'interval': 120,
        if (busyInS != null)
          'busy_until': now.add(Duration(seconds: busyInS)).toIso8601String(),
      };
      expect(heartbeatStale(hb(30), now, interval: 120), isNull);
      expect(heartbeatStale(hb(359), now, interval: 120), isNull);
      expect(heartbeatStale(hb(361), now, interval: 120), contains('stale'));
      expect(heartbeatStale(hb(900, busyInS: 60), now, interval: 120), isNull);
      expect(
        heartbeatStale(hb(900, busyInS: -60), now, interval: 120),
        contains('stale'),
      );
      expect(
        heartbeatStale(null, now, interval: 120),
        contains('out of reach'),
      );
      expect(
        heartbeatStale({'time': 'x'}, now, interval: 120),
        contains('unreadable'),
      );
      expect(heartbeatStale(hb(200), now, interval: 30), isNull);
    });

    String row(
      String svc,
      String state, {
      String health = '',
      String image = 'x',
    }) => jsonEncode({
      'Service': svc,
      'State': state,
      'Health': health,
      'Image': image,
    });

    test('compose ps: JSON lines and a JSON array', () {
      final lines = parseComposePs(
        '${row('server', 'exited')}\n${row('postgres', 'running', health: 'healthy', image: 'postgres:16')}\n',
      );
      expect(lines.map((s) => s.service), ['server', 'postgres']);
      expect(lines.last.isDatabase, isTrue);
      final arr = parseComposePs('[${row('api', 'running')}]');
      expect(arr.single.service, 'api');
    });

    test(
      'heal restarts the failing app services, never a healthy database',
      () {
        final pg = row(
          'postgres',
          'running',
          health: 'healthy',
          image: 'postgres:16-alpine',
        );
        expect(
          servicesToHeal(
            parseComposePs(
              [row('server', 'exited'), row('api', 'running'), pg].join('\n'),
            ),
          ),
          ['server'],
        );
        expect(
          servicesToHeal(
            parseComposePs(
              [
                row('server', 'running'),
                row('api', 'running'),
                row('chrome', 'running'),
                pg,
              ].join('\n'),
            ),
          ),
          ['api', 'server'],
        );
        expect(
          servicesToHeal(
            parseComposePs(
              [
                row('server', 'running', health: 'unhealthy'),
                row(
                  'postgres',
                  'running',
                  health: 'unhealthy',
                  image: 'postgres:16',
                ),
              ].join('\n'),
            ),
          ),
          ['postgres', 'server'],
        );
        expect(
          servicesToHeal(
            parseComposePs(
              [row('nginx', 'exited'), row('server', 'running'), pg].join('\n'),
            ),
          ),
          ['nginx'],
        );
        expect(servicesToHeal(null, serverService: 'app'), ['app']);
      },
    );
  });

  group('registry watch section', () {
    test('round trip; a registry without a watch renders as before', () {
      final plain = Registry();
      expect(plain.render(), isNot(contains('watch:')));
      final reg = Registry()
        ..watch.machine = 'box'
        ..watch.channels['owner'] = {
          'kind': 'email',
          'to': ['me@example.com'],
        }
        ..watch.targets[key] = target();
      final back = Registry.parse(reg.render());
      expect(back.watch.machine, 'box');
      expect(back.watch.interval, 120);
      expect(back.watch.channels['owner']!['to'], ['me@example.com']);
      final t = back.watch.targets[key]!;
      expect(t.heals, isTrue);
      expect(t.checks.single.url, 'https://production.shop.example/health');
      expect(back.render(), reg.render());
    });

    test(
      'merge3 keeps targets of other apps and a deploy keeps the section',
      () {
        final base = Registry()
          ..watch.targets['a/production'] = target(project: 'a');
        final theirs = Registry.parse(base.render())
          ..watch.targets['b/production'] = target(project: 'b');
        final mine = Registry.parse(base.render())
          ..watch.targets['c/staging'] = target(project: 'c', env: 'staging');
        final out = Registry.merge3(base, mine, theirs);
        expect(out.watch.targets.keys.toSet(), {
          'a/production',
          'b/production',
          'c/staging',
        });
        // A write that does not touch the watch (a deploy) keeps it.
        final deploy = Registry.parse(theirs.render())
          ..scheduler = SchedulerSettings(at: '04:00');
        final out2 = Registry.merge3(theirs, deploy, theirs);
        expect(out2.watch.targets.keys, hasLength(2));
      },
    );
  });

  group('fleet', () {
    final config = PodshipConfig.parse('''
project: shop
environments:
  production:
    host: agente@agentes.local
    dir: /Users/agente/podship/shop
    podship_home: /Users/agente/podship
    health:
      url: http://127.0.0.1:{port:web}/health
      public_url: https://shop.example/health
    ports: {web: 20001}
  staging:
    host: local
    dir: /srv/shop-staging
    podship_home: /Users/me/podship
    watch: {heal: false}
    health:
      url: http://127.0.0.1:{port:web}/health
      public_checks:
        - {url: "https://staging.shop.example/health", content_type: application/json}
        - {url: "https://staging.shop.example/mcp", method: post, status: [401]}
    ports: {web: 20002}
  vps:
    host: vps
    dir: /srv/shop
    health: {url: "http://127.0.0.1:1/health"}
''', root: '/work/shop');
    final fleet = FleetConfig.parse({
      'machines': {
        'studio': {'host': 'local', 'home': '/Users/me/podship'},
        'agentes': {
          'host': 'agente@agentes.local',
          'home': '/Users/agente/podship',
        },
      },
      'channels': {
        'owner': {
          'kind': 'email',
          'to': ['me@example.com'],
        },
      },
    });

    test('the owner is the machine with the host; the others mirror', () {
      final prod = config.env('production');
      expect(fleet.ownerOf(prod).name, 'agentes');
      expect(fleet.watchersOf(prod).map((m) => m.name), ['agentes', 'studio']);
      expect(fleet.ownerOf(config.env('staging')).name, 'studio');
    });

    test(
      'heal defaults to true, production included; watch.heal: false turns it off',
      () {
        expect(config.env('production').watch.heal, isTrue);
        expect(config.env('staging').watch.heal, isFalse);
      },
    );

    test('checks: public_checks, else the public_url', () {
      final reg = Registry();
      final staging = config.env('staging');
      final prod = config.env('production');
      final p1 = resolveEnv(config, prod, reg);
      final checks = watchChecks(p1);
      expect(checks.single.url, 'https://shop.example/health');
      final s = watchChecks(resolveEnv(config, staging, reg));
      expect(s.map((c) => c.method), ['GET', 'POST']);
      expect(s.last.status, [401]);
      expect(watchChecks(resolveEnv(config, config.env('vps'), reg)), isEmpty);
    });

    test('applyTo copies the fleet settings and names the machine', () {
      final w = WatchSettings();
      fleet.applyTo(w, fleet.machines.last);
      expect(w.machine, 'agentes');
      expect(w.channels.keys, ['owner']);
    });
  });

  group('watch run', () {
    late Directory home;
    late Map<String, String?> problems;
    late List<List<String>> procs;
    late List<String> notes;
    late bool engineUp;
    late bool localUp;
    late DateTime now;

    WatchRunner runner() => WatchRunner(
      home.path,
      clock: () => now,
      machine: 'box',
      check: (c) async => problems[c.url],
      online: () async => true,
      localOk: (_) async => localUp,
      isMacos: true,
      engineWait: Duration.zero,
      localWait: Duration.zero,
      pollEvery: Duration.zero,
      process: (exe, args, {environment, cwd, timeout = Duration.zero}) async {
        procs.add([
          if (environment?['PODSHIP_LOCAL_ENV'] != null)
            'PODSHIP_LOCAL_ENV=${environment!['PODSHIP_LOCAL_ENV']}',
          exe,
          ...args,
        ]);
        if (exe == 'docker') {
          return (code: engineUp ? 0 : 1, out: engineUp ? '28.0.1' : '');
        }
        if (exe == 'bash') return (code: 1, out: '');
        if (exe == 'open') {
          engineUp = true;
          return (code: 0, out: '');
        }
        if (args.contains('restart')) {
          localUp = true;
          problems.clear();
          return (code: 0, out: 'healthy after 3 check(s)');
        }
        return (code: 0, out: '');
      },
      notifier: Notifier(
        NotifyConfig(
          events: const [NotifyEvent.watchDown, NotifyEvent.watchRecovered],
          channels: [NotifyChannel(name: 'macos', kind: 'macos')],
        ),
        macos: true,
        run: (exe, args) async {
          notes.add(args.join(' '));
          return ProcessResult(0, 0, '', '');
        },
      ),
    );

    setUp(() {
      home = Directory.systemTemp.createTempSync('podship-watch-');
      problems = {};
      procs = [];
      notes = [];
      engineUp = true;
      localUp = true;
      now = DateTime(2026, 10, 8, 9, 26);
      final reg = Registry()
        ..watch.machine = 'box'
        ..watch.engine = Engine.dockerDesktop
        ..watch.targets[key] = target()
        ..watch.targets['shop/staging'] = target(env: 'staging')
        ..watch.targets['other/production'] = target(
          project: 'other',
          owner: false,
        );
      File(p.join(home.path, 'registry.yaml')).writeAsStringSync(reg.render());
    });

    tearDown(() => home.deleteSync(recursive: true));

    Future<WatchRun> tick() async {
      final r = await runner().run();
      now = now.add(const Duration(minutes: 2));
      return r!;
    }

    test(
      'the 2026-10-08 outage: the engine is dead; one alert, the engine starts, '
      'podship restart runs, one "recovered" with the downtime',
      () async {
        problems = {
          'https://production.shop.example/health':
              'https://shop.example/health: status 502',
        };
        engineUp = false;
        localUp = false;
        final r1 = await tick();
        expect(r1.outcomes[key], Outcome.fail);
        expect(r1.notifications, isEmpty);
        expect(procs, isEmpty);

        final r2 = await tick();
        expect(r2.notifications.single.event, NotifyEvent.watchDown);
        expect(r2.notifications.single.title, 'DOWN $key (seen from box)');
        expect(
          procs.map((x) => x.first),
          containsAllInOrder(['docker', 'open', 'docker']),
        );
        final restart = procs.last;
        expect(
          restart,
          containsAllInOrder([
            'PODSHIP_LOCAL_ENV=production',
            '-C',
            '/srv/shop/current',
            'restart',
            '--env',
            'production',
            'server',
          ]),
        );
        expect(r2.events.map((e) => e.event), ['down', 'engine_start', 'heal']);
        expect(r2.events.last.ok, isTrue);

        final r3 = await tick();
        expect(r3.notifications.single.event, NotifyEvent.watchRecovered);
        expect(
          r3.notifications.single.body,
          contains('4 min 00 s of downtime'),
        );
        expect(r3.events.single.downtime, const Duration(minutes: 4));
        expect(notes, hasLength(2), reason: 'one alert, one recovery');

        final hist = runner().history();
        expect(hist.map((e) => e.event), [
          'down',
          'engine_start',
          'heal',
          'recovered',
        ]);
        final state =
            jsonDecode(
                  File(
                    p.join(home.path, 'watch', 'state.json'),
                  ).readAsStringSync(),
                )
                as Map;
        expect((state['targets'] as Map)[key]['fails'], 0);
      },
    );

    test(
      'healthy on this machine but not in public: no restart, the alert says why',
      () async {
        problems = {'https://production.shop.example/health': 'status 530'};
        localUp = true;
        await tick();
        final r = await tick();
        expect(procs.where((x) => x.contains('restart')), isEmpty);
        expect(r.events.last.detail, contains('tunnel or DNS'));
      },
    );

    test('a cross-watch target alerts and never heals', () async {
      problems = {
        'https://production.other.example/health': 'connection refused',
      };
      await tick();
      final r = await tick();
      expect(r.notifications.single.title, contains('other/production'));
      expect(r.notifications.single.body, contains('nobody heals it'));
      expect(procs, isEmpty);
    });

    test(
      'cross-watch with a heartbeat: the live owner alerts, not this machine; '
      'a dead owner: this machine alerts once',
      () async {
        final reg = Registry.parse(
          File(p.join(home.path, 'registry.yaml')).readAsStringSync(),
        );
        final t = target(project: 'other', owner: false);
        reg.watch.targets['other/production'] = WatchTarget(
          project: t.project,
          env: t.env,
          checks: t.checks,
          owner: false,
          machine: 'peer',
          heal: false,
          heartbeatHost: 'peer-host',
          heartbeatPath: '/h/watch/heartbeat.json',
        );
        File(
          p.join(home.path, 'registry.yaml'),
        ).writeAsStringSync(reg.render());
        Map<String, Object?>? beat = {
          'time': now.toUtc().toIso8601String(),
          'interval': 120,
        };
        var asked = 0;
        WatchRunner r() => WatchRunner(
          home.path,
          clock: () => now,
          machine: 'box',
          check: (c) async => problems[c.url],
          online: () async => true,
          heartbeat: (_) async {
            asked++;
            return beat;
          },
          notifier: Notifier(
            NotifyConfig(
              events: const [NotifyEvent.watchDown, NotifyEvent.watchRecovered],
              channels: [NotifyChannel(name: 'macos', kind: 'macos')],
            ),
            macos: true,
            run: (exe, args) async {
              notes.add(args.join(' '));
              return ProcessResult(0, 0, '', '');
            },
          ),
        );
        Future<WatchRun> go() async {
          beat = beat == null
              ? null
              : {...beat!, 'time': now.toUtc().toIso8601String()};
          final x = (await r().run())!;
          now = now.add(const Duration(minutes: 2));
          return x;
        }

        problems = {'https://production.other.example/health': 'status 502'};
        // Case 1: the owner's watch is alive: no alert from here.
        for (var i = 0; i < 4; i++) {
          expect((await go()).notifications, isEmpty);
        }
        expect(asked, greaterThan(0));
        // The owner heals it: no "recovered" from here either.
        problems = {};
        expect((await go()).notifications, isEmpty);
        // Case 2: the owner machine is out of reach (ssh fails): one alert.
        problems = {'https://production.other.example/health': 'status 502'};
        beat = null;
        await go();
        final down = await go();
        expect(down.notifications.single.title, contains('other/production'));
        expect(down.notifications.single.body, contains('nobody heals it'));
        expect((await go()).notifications, isEmpty, reason: 'once');
        problems = {};
        expect(
          (await go()).notifications.single.event,
          NotifyEvent.watchRecovered,
        );
        // The heartbeat file of this machine exists for the others.
        final hb =
            jsonDecode(
                  File(
                    p.join(home.path, 'watch', 'heartbeat.json'),
                  ).readAsStringSync(),
                )
                as Map;
        expect(hb['machine'], 'box');
      },
    );

    test('no internet on this machine: failures do not count', () async {
      problems = {
        'https://production.shop.example/health': 'x',
        'https://production.other.example/health': 'x',
      };
      final w = WatchRunner(
        home.path,
        clock: () => now,
        check: (c) async => problems[c.url],
        online: () async => false,
        notifier: Notifier(NotifyConfig(channels: const []), macos: false),
      );
      for (var i = 0; i < 5; i++) {
        final r = await w.run();
        expect(r!.outcomes.values.toSet(), {Outcome.pass, Outcome.unknown});
        expect(r.notifications, isEmpty);
      }
    });

    test(
      'an older podship drops the watch: section; the watch uses its copy',
      () async {
        await tick();
        // A deploy by a podship older than the watch rewrites the registry.
        File(
          p.join(home.path, 'registry.yaml'),
        ).writeAsStringSync(Registry().render());
        final r = await tick();
        expect(r.outcomes.keys, hasLength(3));
        // An explicit empty section (watch uninstall) wins over the copy.
        final empty = Registry()..watch.machine = 'box';
        File(
          p.join(home.path, 'registry.yaml'),
        ).writeAsStringSync(empty.render());
        expect((await tick()).outcomes, isEmpty);
      },
    );

    test('two targets down in one run: one alert for both', () async {
      problems = {
        'https://production.shop.example/health': 'x',
        'https://production.other.example/health': 'y',
      };
      await tick();
      final r = await tick();
      expect(r.notifications, hasLength(1));
      expect(r.notifications.single.title, contains('other/production'));
      expect(r.notifications.single.title, contains(key));
    });
  });

  group('agent', () {
    test(
      'with watch targets the plist ticks every interval, in the same agent',
      () {
        final plain = schedulerPlist(
          home: '/h',
          settings: SchedulerSettings(at: '03:00'),
          path: '/bin',
        );
        expect(plain, isNot(contains('StartInterval')));
        final watched = schedulerPlist(
          home: '/h',
          settings: SchedulerSettings(at: '03:00'),
          path: '/bin',
          watchInterval: 120,
        );
        expect(
          watched,
          contains('<key>StartInterval</key><integer>120</integer>'),
        );
        expect(
          watched,
          contains('<key>Label</key><string>$schedulerLabel</string>'),
        );
        expect(watched, contains('<key>Hour</key><integer>3</integer>'));
        final sd = schedulerSystemd(
          home: '/h',
          settings: SchedulerSettings(at: '03:00'),
          path: '/bin',
          watchInterval: 120,
        );
        expect(sd.timer, contains('OnUnitActiveSec=120s'));
        expect(sd.service, contains('KillMode=process'));
      },
    );

    test(
      'nightly jobs wait for the nightly time even when the agent ticks all day',
      () {
        final reg = Registry()
          ..scheduler = SchedulerSettings(at: '03:00')
          ..putJob(
            ScheduledJob(
              kind: JobKind.backup,
              project: 'a',
              env: 'production',
              conf: '/x.conf',
            ),
          );
        final st = SchedulerState();
        for (final j in reg.jobs.values) {
          st.jobs[j.id] = JobState(lastRunDate: '2026-10-07');
        }
        expect(dueJobs(reg, st, DateTime(2026, 10, 8, 0, 2)), isEmpty);
        expect(dueJobs(reg, st, DateTime(2026, 10, 8, 2, 58)), isEmpty);
        expect(dueJobs(reg, st, DateTime(2026, 10, 8, 3, 0)), hasLength(1));
      },
    );
  });
}
