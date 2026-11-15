@Tags(['unit'])
library;

import 'dart:io';

import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/bluegreen.dart';
import 'package:podship/src/ops/scripts.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/release_ops.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/release/layout.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const composeJson = '''
{"name":"demo","services":{
 "server":{"ports":[{"mode":"ingress","host_ip":"127.0.0.1","target":8082,"published":"8087","protocol":"tcp"}]},
 "api":{"ports":[{"host_ip":"127.0.0.1","target":8080,"published":"8086"}]},
 "chrome":{"network_mode":"service:server"}},
 "volumes":{"tickets":{"name":"demo_tickets"},"pacewright":{}}}
''';

const presenteJson = '''
{"name":"presente","services":{
 "nginx":{"depends_on":{"server":{"condition":"service_started","required":true}},
   "ports":[{"mode":"ingress","host_ip":"127.0.0.1","target":8080,"published":"8360","protocol":"tcp"}]},
 "postgres":{"volumes":[{"type":"volume","source":"pgdata","target":"/var/lib/postgresql/data"}]},
 "server":{"depends_on":{"postgres":{"condition":"service_healthy","required":true}}}},
 "volumes":{"pgdata":{"name":"presente_pgdata"}}}
''';

bool bashOk(String script) {
  final f = File(
    '${Directory.systemTemp.path}/podship-bg-${DateTime.now().microsecondsSinceEpoch}.sh',
  )..writeAsStringSync(script);
  try {
    return Process.runSync('bash', ['-n', f.path]).exitCode == 0;
  } finally {
    f.deleteSync();
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

void main() {
  test('compose config gives the published ports and the volumes', () {
    final c = parseComposeConfig(composeJson);
    expect(c.ports, [
      PublishedPort('server', '127.0.0.1', 8087, 8082),
      PublishedPort('api', '127.0.0.1', 8086, 8080),
    ]);
    expect(c.volumes, ['tickets', 'pacewright']);
  });

  test('a color publishes nothing and joins the front network', () {
    final c = parseComposeConfig(composeJson);
    final o = colorOverride(
      composeProject: 'demo',
      color: 'green',
      ports: c.ports,
      volumes: c.volumes,
    );
    expect(o, contains('"server":\n    ports: !reset []'));
    expect(o, contains('aliases: ["green-server"]'));
    expect(o, contains('"demo-front":\n    external: true'));
    expect(o, contains('"tickets":\n    name: "demo_tickets"'));
  });

  test('the front passes TCP to the active color', () {
    final c = parseComposeConfig(composeJson);
    final f = frontConf(c.ports, 'blue');
    expect(f, contains('stream {'));
    expect(f, contains('listen 8087;'));
    expect(f, contains(r'set $up blue-server:8082;'));
    expect(f, contains(r'set $up blue-api:8080;'));
    expect(f, contains('resolver 127.0.0.11'));
  });

  test('colors alternate', () {
    expect(otherColor(null), 'blue');
    expect(otherColor('blue'), 'green');
    expect(otherColor('green'), 'blue');
  });

  test('the first flip stops the base project, later ones reload', () {
    final env = PodshipConfig.parse(sampleConfig).env('production');
    final s = flipScript(
      l: EnvLayout(env),
      composeProject: 'demo',
      color: 'blue',
      ports: parseComposeConfig(composeJson).ports,
      stopBase: stopBaseScript('demo'),
    );
    expect(s, contains('nginx -s reload'));
    expect(s, contains('label=com.docker.compose.project=demo)'));
    expect(s, contains('-p 127.0.0.1:8087:8087'));
    expect(s, contains('echo demo-blue > /srv/demo/.podship/active-project'));
  });

  test('compose.sh follows the active color and is valid bash', () {
    final s = composeSh(
      composeProject: 'demo',
      releaseDir: '/srv/demo/releases/r1',
      composeFiles: ['docker-compose.yml'],
      blueGreenState: '/srv/demo/.podship',
    );
    expect(s, contains('PODSHIP_COMPOSE_PROJECT:-'));
    expect(s, contains('/srv/demo/.podship/active-project'));
    expect(s, contains(r'${bg[@]+"${bg[@]}"}'));
    final f = File('${Directory.systemTemp.path}/podship-bg-compose.sh')
      ..writeAsStringSync(s);
    expect(Process.runSync('bash', ['-n', f.path]).exitCode, 0);
    f.deleteSync();
  });

  group('stable services (per-env database)', () {
    final c = parseComposeConfig(presenteJson);

    test('compose config gives depends_on', () {
      expect(c.services['server']!.dependsOn.keys, ['postgres']);
      expect(c.services['nginx']!.dependsOn.keys, ['server']);
    });

    test('a color disables them, keeps the other dependencies', () {
      final o = colorOverride(
        composeProject: 'presente',
        color: 'green',
        ports: c.ports,
        volumes: c.volumes,
        services: c.services,
        stable: ['postgres'],
      );
      expect(
        o,
        contains(
          '"postgres":\n    profiles: ["podship-stable"]\n    ports: !reset []\n    volumes: !reset []',
        ),
      );
      expect(o, contains('"server":\n    depends_on: !reset {}'));
      expect(o, isNot(contains('"nginx":\n    depends_on')));
      expect(o, contains('aliases: ["green-nginx"]'));
      expect(
        o,
        contains(
          '  default:\n    name: "presente-green-net"\n    external: true',
        ),
      );
      final mixed = colorOverride(
        composeProject: 'presente',
        color: 'blue',
        ports: c.ports,
        volumes: c.volumes,
        services: {
          ...c.services,
          'worker': ComposeService(
            'worker',
            dependsOn: {
              'postgres': {'condition': 'service_healthy'},
              'server': {'condition': 'service_started'},
            },
          ),
        },
        stable: ['postgres'],
      );
      expect(
        mixed,
        contains(
          '"worker":\n    depends_on: !override {"server":{"condition":"service_started"}}',
        ),
      );
    });

    test('without stable services the default network stays', () {
      final o = colorOverride(
        composeProject: 'presente',
        color: 'green',
        ports: c.ports,
        volumes: c.volumes,
        services: c.services,
      );
      expect(o, isNot(contains('presente-green-net')));
      expect(o, isNot(contains('profiles')));
    });

    test('compose.sh of a color joins them to its network; valid bash', () {
      final s = composeSh(
        composeProject: 'presente',
        releaseDir: '/srv/presente/releases/r1',
        composeFiles: ['docker-compose.yml'],
        blueGreenState: '/srv/presente/.podship',
        stable: ['postgres'],
      );
      expect(s, contains('presente-blue|presente-green)'));
      expect(
        s,
        contains(r'docker network connect --alias postgres "$net" "$c"'),
      );
      expect(
        s.indexOf('network connect'),
        lessThan(s.indexOf('exec docker compose')),
      );
      expect(bashOk(s), isTrue);
    });

    test('a color starts with the stable services up, never recreated', () {
      final env = PodshipConfig.parse(sampleConfig).env('production');
      final s = startColorScript(
        l: EnvLayout(env),
        composeProject: 'presente',
        id: 'r2',
        color: 'blue',
        override: '# o\n',
        serverService: 'nginx',
        serverPort: 8080,
        healthPaths: ['/health', '/readyz'],
        stable: ['postgres'],
        migrate: 'run --rm --no-deps server',
        checks: [
          PublicCheck(
            url: 'https://app.example.com/health',
            contentType: 'application/json',
            contains: '"ok":true',
          ),
        ],
      );
      final up = s.indexOf('PODSHIP_COMPOSE_PROJECT=presente ');
      final join = s.indexOf('network connect');
      final guard = s.indexOf('grep -qx postgres');
      final migrate = s.indexOf('run --rm --no-deps server');
      final colorUp = s.indexOf('up -d --no-build --remove-orphans');
      final check = s.indexOf('passes ');
      expect(s, contains('up -d --no-build --no-recreate --wait postgres'));
      expect([
        up,
        join,
        guard,
        migrate,
        colorUp,
        check,
      ], everyElement(greaterThan(-1)));
      expect(up < join && join < guard && guard < migrate, isTrue);
      expect(migrate < colorUp && colorUp < check, isTrue);
      expect(bashOk(s), isTrue);
    });

    test(
      'the first flip frees the ports first, then stops the rest but the stable ones',
      () {
        final env = PodshipConfig.parse(sampleConfig).env('production');
        final s = flipScript(
          l: EnvLayout(env),
          composeProject: 'presente',
          color: 'blue',
          ports: c.ports,
          stopBase: stopBaseScript(
            'presente',
            front: ['nginx'],
            stable: ['postgres'],
          ),
          afterBase: stopBaseRestScript('presente', stable: ['postgres']),
        );
        final stopNginx = s.indexOf('com.docker.compose.service=nginx');
        final run = s.indexOf('docker run -d --name presente-front');
        final rest = s.indexOf(
          r'case " postgres " in *" $s "*) continue;; esac',
        );
        expect(stopNginx, greaterThan(-1));
        expect(stopNginx < run && run < rest, isTrue);
        expect(bashOk(s), isTrue);
      },
    );

    test(
      'the old color stops its port services first, with the drain time',
      () {
        final s = stopColorScript(
          'presente',
          'green',
          front: ['nginx'],
          drainSeconds: 45,
          graceSeconds: 30,
        );
        final drain = s.indexOf('docker stop -t 45');
        final rest = s.indexOf('docker stop -t 30');
        expect(s, contains('com.docker.compose.service=nginx'));
        expect(drain, greaterThan(-1));
        expect(drain, lessThan(rest));
        expect(bashOk(s), isTrue);
      },
    );

    test('an in-place switch leaves blue/green first', () {
      final env = PodshipConfig.parse(sampleConfig).env('production');
      final s = switchTo(EnvLayout(env), 'r3', action: 'deploy');
      expect(s, contains('docker rm -f demo-front'));
      expect(s, contains('rm -f /srv/demo/.podship/active-project'));
      // The stable services leave the color networks, which go.
      expect(s, contains('demo-blue-net demo-green-net demo-front'));
      expect(s, contains(r'docker network disconnect -f "$n" "$c"'));
      expect(
        s,
        contains(
          'docker ps -aq --filter label=com.docker.compose.project=demo)',
        ),
      );
      expect(s.indexOf('demo-front'), lessThan(s.indexOf('up -d --no-build')));
      expect(bashOk(s), isTrue);
    });
  });

  group('public checks before the flip', () {
    // A fake `docker` that answers `docker exec <c> wget ...` like busybox.
    String run(PublicCheck c, String reply) {
      final dir = Directory.systemTemp.createTempSync('podship-pf');
      try {
        File('${dir.path}/docker')
          ..writeAsStringSync(
            '#!/bin/sh\necho "\$@" > ${dir.path}/args\ncat ${dir.path}/reply\n',
          )
          ..also((f) => Process.runSync('chmod', ['755', f.path]));
        File('${dir.path}/reply').writeAsStringSync(reply);
        final script =
            'set -eu\nc=x\nsleep() { :; }\n${preflightCheckScript(c, 8080, 'blue')}';
        final r = Process.runSync(
          'bash',
          ['-c', script],
          environment: {'PATH': '${dir.path}:${Platform.environment['PATH']}'},
        );
        final args = File('${dir.path}/args').readAsStringSync();
        return '${r.exitCode}|$args|${r.stdout}${r.stderr}';
      } finally {
        dir.deleteSync(recursive: true);
      }
    }

    const okJson =
        'Connecting to 127.0.0.1:8080\n  HTTP/1.1 200 OK\n  Content-Type: application/json\n\n{"ok":true}\n';

    test('passes on status, type and body, with the Host header', () {
      final out = run(
        PublicCheck(
          url: 'https://app.example.com/health',
          contentType: 'application/json',
          contains: '"ok":true',
        ),
        okJson,
      );
      expect(out, startsWith('0|'));
      expect(out, contains('Host: app.example.com'));
      expect(out, contains('http://127.0.0.1:8080/health'));
    });

    test('a 2xx with the wrong content type fails', () {
      final out = run(
        PublicCheck(
          url: 'https://app.example.com/health',
          contentType: 'text/html',
        ),
        okJson,
      );
      expect(out, startsWith('1|'));
    });

    test('fails on a wrong body', () {
      final out = run(
        PublicCheck(url: 'https://app.example.com/health', contains: 'nope'),
        okJson,
      );
      expect(out, startsWith('1|'));
      expect(out, contains('blue fails the public check'));
    });

    test(
      'an expected 400 of a POST passes on its status (busybox prints no headers)',
      () {
        final out = run(
          PublicCheck(
            url: 'https://app.example.com/rpc/nothing-here',
            method: 'post',
            status: [400, 404],
            contentType: 'text/plain',
          ),
          // What busybox wget prints for a 4xx (staging, 2026-11-14): no
          // headers, no body.
          'Connecting to 127.0.0.1:8080 (127.0.0.1:8080)\n  HTTP/1.1 400 Bad Request\nwget: server returned error: HTTP/1.1 400 Bad Request\n',
        );
        expect(out, startsWith('0|'));
        expect(out, contains('--post-data='));
      },
    );

    test('an unexpected 200 fails a check that wants 404', () {
      final out = run(
        PublicCheck(url: 'https://app.example.com/rpc/x', status: [404]),
        okJson,
      );
      expect(out, startsWith('1|'));
    });
  });

  group('plans', () {
    final text = sampleConfig.replaceFirst(
      '    database: {name: demo}\n',
      '    database: {name: demo, mode: shared}\n    switch: blue_green\n',
    );
    final config = PodshipConfig.parse(text, root: '/work/demo');
    final ctx = Ctx(
      config: config,
      ssh: Ssh(),
      log: Log.silent(),
      dryRun: true,
    );
    final s = parseState(
      'CURRENT 20261002-000000-bbbbbbb\n'
      'R 20261002-000000-bbbbbbb ok {"id":"x","sha":"abc","images":[]}\n'
      'R 20261001-000000-aaaaaaa ok {"id":"y","sha":"abd","images":[]}\n'
      'ENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
    );
    final r = resolveEnv(
      config,
      config.env('production'),
      s.registry,
      listening: s.listening,
    );

    test('a per-env database is a stable service, not a blocker', () {
      expect(blueGreenBlocker(config.env('production')), isNull);
      expect(config.env('production').stableServices, isEmpty);
      final perEnv = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '    database: {name: demo}\n',
          '    database: {name: demo}\n    switch: blue_green\n',
        ),
      ).env('production');
      expect(blueGreenBlocker(perEnv), isNull);
      expect(perEnv.stableServices, ['postgres']);
      expect(perEnv.blueGreen.drainSeconds, 30);
      final custom = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '    database: {name: demo}\n',
          '    database: {name: demo}\n    switch: blue_green\n'
              '    blue_green: {stable: [postgres, redis], drain: 45}\n',
        ),
      ).env('production');
      expect(custom.stableServices, ['postgres', 'redis']);
      expect(custom.blueGreen.drainSeconds, 45);
    });

    test('deploy starts the new color, checks health, then stops the old', () {
      final p = planDeploy(
        ctx: ctx,
        r: r,
        state: s,
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 6, 16),
        snapshot: '/tmp/snap',
      );
      final titles = p.steps.map((x) => x.title).toList();
      expect(titles, isNot(contains(startsWith('Switch to'))));
      final start = titles.indexWhere(
        (t) => t.startsWith('Start') && t.contains('(blue/green)'),
      );
      expect(start, p.guardFrom);
      expect(titles[start + 1], 'Health check');
      expect(titles.last, 'Stop the old color');
      expect(p.recovery.map((x) => x.title), contains('Flip the front back'));
    });

    test('rollback flips too', () {
      final p = planRollback(ctx: ctx, r: r, state: s);
      expect(p.steps.first.title, contains('(blue/green)'));
      expect(p.recovery.single.title, 'Flip the front back');
      // The API records the target from the title: no `Switch to` step
      // (staging 2026-11-14: "Bad state: No element" after a good flip).
      expect(rollbackTarget(p), '20261001-000000-aaaaaaa');
    });

    final perEnvText = sampleConfig.replaceFirst(
      '    database: {name: demo}\n',
      '    database: {name: demo}\n    switch: blue_green\n'
          '    migrations: maintenance\n',
    );
    final c2 = PodshipConfig.parse(perEnvText, root: '/work/demo');
    final ctx2 = Ctx(config: c2, ssh: Ssh(), log: Log.silent(), dryRun: true);
    Plan plan2({bool allow = false, EnvState? state}) => planDeploy(
      ctx: ctx2,
      r: resolveEnv(c2, c2.env('production'), s.registry),
      state: state ?? s,
      git: GitInfo('a0dc2b0123456789', ref: 'main'),
      now: DateTime.utc(2026, 10, 6, 16),
      snapshot: '/tmp/snap',
      options: DeployOptions(allowDestructiveMigrations: allow),
    );

    test(
      'per-env database: blue/green, migrations checked, then in the color',
      () {
        final titles = plan2().steps.map((x) => x.title).toList();
        expect(titles, isNot(contains('Switch mode: in place')));
        expect(titles, isNot(contains('Apply migrations')));
        final check = titles.indexOf('Check the new migrations (blue/green)');
        final start = titles.indexWhere(
          (t) => t.contains('(blue/green)') && t.startsWith('Start'),
        );
        expect(check, greaterThan(0));
        expect(check, lessThan(titles.indexOf('Upload files')));
        expect(start, greaterThan(check));
        expect(
          plan2().steps[start].describe(),
          contains('migrations in the new color'),
        );
        expect(
          plan2().steps[start].describe(),
          contains('postgres stay in demo'),
        );
      },
    );

    test('the first deploy has nothing to check', () {
      final first = parseState(
        'CURRENT \nENVFILE yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
      );
      final titles = plan2(state: first).steps.map((x) => x.title).toList();
      expect(titles, isNot(contains('Check the new migrations (blue/green)')));
    });

    test(
      '--allow-destructive-migrations switches in place, with the reason',
      () {
        final titles = plan2(allow: true).steps.map((x) => x.title).toList();
        expect(titles, contains('Switch mode: in place'));
        expect(titles, contains(startsWith('Switch to')));
        expect(titles, contains('Apply migrations'));
        expect(
          titles,
          isNot(contains('Check the new migrations (blue/green)')),
        );
      },
    );
  });

  group('review 2026-11-14', () {
    test('H1: a front with no ports is refused', () {
      expect(() => frontConf(const [], 'blue'), throwsArgumentError);
    });

    test('H3: blue_green.stable adds to the database service', () {
      final env = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '    database: {name: demo}\n',
          '    database: {name: demo}\n    switch: blue_green\n'
              '    blue_green: {stable: [redis]}\n',
        ),
      ).env('production');
      expect(env.stableServices, ['postgres', 'redis']);
    });

    group('H2: compose.sh sends the stable services to the base project', () {
      late Directory dir;
      late String sh;
      setUp(() {
        dir = Directory.systemTemp.createTempSync('podship-route');
        Directory('${dir.path}/bin').createSync();
        Directory('${dir.path}/state').createSync();
        File(
          '${dir.path}/state/active-project',
        ).writeAsStringSync('presente-blue\n');
        File('${dir.path}/bin/docker').writeAsStringSync('''
#!/bin/bash
echo "\$*" >> ${dir.path}/calls
case "\$1 \$2" in
  "network inspect") [ "\$3" = presente-blue-net ];;
  "ps -q") case "\$*" in *service=postgres*) echo c1;; esac;;
esac
''');
        Process.runSync('chmod', ['755', '${dir.path}/bin/docker']);
        sh = '${dir.path}/compose.sh';
        File(sh).writeAsStringSync(
          composeSh(
            composeProject: 'presente',
            releaseDir: '${dir.path}/r1',
            composeFiles: ['docker-compose.yml'],
            blueGreenState: '${dir.path}/state',
            stable: ['postgres'],
          ),
        );
      });
      tearDown(() => dir.deleteSync(recursive: true));

      List<String> run(List<String> args) {
        File('${dir.path}/calls').writeAsStringSync('');
        final r = Process.runSync(
          'bash',
          [sh, ...args],
          environment: {
            'PATH': '${dir.path}/bin:${Platform.environment['PATH']}',
          },
        );
        expect(r.exitCode, 0, reason: '${r.stderr}');
        return File('${dir.path}/calls').readAsLinesSync();
      }

      String project(List<String> calls) => RegExp(
        r'^compose -p (\S+)',
      ).firstMatch(calls.firstWhere((c) => c.startsWith('compose')))!.group(1)!;

      test('up -d postgres goes to the base project and joins again', () {
        final calls = run(['up', '-d', '--force-recreate', 'postgres']);
        expect(project(calls), 'presente');
        final up = calls.indexWhere((c) => c.startsWith('compose'));
        expect(
          calls.skip(up),
          contains('network connect --alias postgres presente-blue-net c1'),
        );
        expect(
          calls.skip(up),
          isNot(contains(contains('presente-green-net c1'))),
        );
      });

      test('exec, logs and restart of postgres too', () {
        expect(project(run(['exec', 'postgres', 'psql'])), 'presente');
        expect(project(run(['logs', '--tail', '5', 'postgres'])), 'presente');
        expect(project(run(['restart', 'postgres'])), 'presente');
      });

      test(
        'a color service stays in the color, also with "postgres" as a value',
        () {
          expect(project(run(['up', '-d'])), 'presente-blue');
          expect(
            project(run(['exec', '-u', 'postgres', 'server', 'psql'])),
            'presente-blue',
          );
          expect(
            project(
              run([
                'run', '--rm', '--no-deps', '-T', '--name', 'x', //
                '--entrypoint', 'postgres', 'server',
              ]),
            ),
            'presente-blue',
          );
        },
      );
    });

    final perEnvText = sampleConfig.replaceFirst(
      '    database: {name: demo}\n',
      '    database: {name: demo}\n    switch: blue_green\n'
          '    migrations: maintenance\n',
    );
    final c3 = PodshipConfig.parse(perEnvText, root: '/work/demo');
    final ctx3 = Ctx(config: c3, ssh: Ssh(), log: Log.silent(), dryRun: true);
    final s3 = parseState(
      'CURRENT 20261002-000000-bbbbbbb\n'
      'R 20261002-000000-bbbbbbb ok {"id":"x","sha":"abc","images":[]}\n'
      'R 20261001-000000-aaaaaaa ok {"id":"y","sha":"abd","images":[]}\n'
      'ENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
    );
    final r3 = resolveEnv(c3, c3.env('production'), s3.registry);

    test('M6: restart is a blue/green start of the current release', () {
      final p = planRestart(ctx: ctx3, r: r3, state: s3);
      expect(p.title, contains('blue/green'));
      expect(p.steps.first.title, startsWith('Start 20261002-000000-bbbbbbb'));
      expect(p.steps.last.title, 'Stop the old color');
      expect(p.recovery.single.title, 'Flip the front back');
    });

    test('M6: restart of named services warns; stable and color not mixed', () {
      final db = planRestart(
        ctx: ctx3,
        r: r3,
        state: s3,
        services: ['postgres'],
      );
      expect(db.steps.first.describe(), contains('base project'));
      expect(
        db.steps[1].describe(),
        contains('--force-recreate --no-deps postgres'),
      );
      final app = planRestart(
        ctx: ctx3,
        r: r3,
        state: s3,
        services: ['server'],
      );
      expect(app.steps.first.describe(), contains('short outage'));
      expect(
        () => planRestart(
          ctx: ctx3,
          r: r3,
          state: s3,
          services: ['server', 'postgres'],
        ),
        throwsA(isA<Aborted>()),
      );
    });

    test('M7: the new front config is tested before it replaces the old', () {
      final f = flipScript(
        l: EnvLayout(c3.env('production')),
        composeProject: 'demo',
        color: 'green',
        ports: [PublishedPort('nginx', '127.0.0.1', 8087, 8080)],
      );
      final t = f.indexOf('nginx -t -q -c /etc/podship-front/next.conf');
      final mv = f.indexOf('next.conf\' \'');
      final reload = f.indexOf('nginx -s reload');
      expect(t, greaterThan(0));
      expect(f.indexOf('mv -f', t), lessThan(reload));
      expect(mv, isNot(0));
      expect(f.indexOf('active-project'), greaterThan(reload));
      // The front image is there before the base project stops.
      expect(
        f.indexOf('docker pull'),
        lessThan(f.indexOf('docker run -d --name demo-front')),
      );
      expect(bashOk(f), isTrue);
    });

    test('M7: the front config names the active color', () {
      expect(
        activeProject(
          composeProject: 'demo',
          recorded: 'demo-blue',
          frontColor: 'green',
        ),
        'demo-green',
      );
      expect(
        activeProject(composeProject: 'demo', recorded: '', frontColor: ''),
        '',
      );
      expect(
        () => activeProject(
          composeProject: 'demo',
          recorded: 'demo-blue',
          frontColor: '',
        ),
        throwsA(isA<Aborted>()),
      );
      final dir = Directory.systemTemp.createTempSync('podship-front');
      try {
        File('${dir.path}/nginx.conf').writeAsStringSync(
          frontConf([PublishedPort('nginx', '127.0.0.1', 1, 2)], 'green'),
        );
        final l = EnvLayout(c3.env('production'));
        final script = frontColorScript(l, 'demo')
            .replaceFirst(
              RegExp(r'^docker container inspect \S+ >/dev/null 2>&1 && '),
              '',
            )
            .replaceAll(
              '${l.state}/front/nginx.conf',
              '${dir.path}/nginx.conf',
            );
        expect(
          (Process.runSync('bash', ['-c', script]).stdout as String).trim(),
          'green',
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test(
      'rollback and promote check the migrations; the flag switches in place',
      () {
        final p = planRollback(ctx: ctx3, r: r3, state: s3);
        final titles = p.steps.map((x) => x.title).toList();
        expect(titles.first, 'Check the migrations (blue/green)');
        expect(p.guardFrom, 1);
        final inPlace = planRollback(
          ctx: ctx3,
          r: r3,
          state: s3,
          allowDestructiveMigrations: true,
        );
        final t2 = inPlace.steps.map((x) => x.title).toList();
        expect(t2, contains('Switch mode: in place'));
        expect(t2, contains(startsWith('Switch to')));
        expect(t2, isNot(contains('Check the migrations (blue/green)')));
        expect(rollbackTarget(inPlace), '20261001-000000-aaaaaaa');
      },
    );

    test('the rollback target is the last " to " of the title', () {
      expect(
        rollbackTarget(Plan('rollback go to env from a to b (code only)', [])),
        'b',
      );
    });

    test('--allow-destructive-migrations migrates in the base project', () {
      final p = planDeploy(
        ctx: ctx3,
        r: r3,
        state: s3,
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 6, 16),
        snapshot: '/tmp/snap',
        options: DeployOptions(allowDestructiveMigrations: true),
      );
      final m = p.steps.firstWhere((x) => x.title == 'Apply migrations');
      expect(m.describe(), contains('PODSHIP_COMPOSE_PROJECT=demo'));
    });

    test('a failed public check hides Set-Cookie', () {
      expect(
        preflightCheckScript(PublicCheck(url: 'https://x.test/'), 8080, 'blue'),
        contains("grep -vi '^ *set-cookie:'"),
      );
    });

    test('a changed stable service is reported, never recreated', () {
      final s = stableDriftScript('demo', '/r/compose.sh', ['postgres']);
      expect(s, contains('config --hash'));
      expect(s, contains('podship restart postgres'));
      expect(bashOk(s), isTrue);
    });
  });
}
