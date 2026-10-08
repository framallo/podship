@Tags(['unit'])
library;

import 'dart:io';

import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/bluegreen.dart';
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

    test('blue/green needs a shared database', () {
      expect(blueGreenBlocker(config.env('production')), isNull);
      final perEnv = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '    database: {name: demo}\n',
          '    database: {name: demo}\n    switch: blue_green\n',
        ),
      ).env('production');
      expect(blueGreenBlocker(perEnv), contains('database.mode: shared'));
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
      final start = titles.indexWhere((t) => t.contains('(blue/green)'));
      expect(start, p.guardFrom);
      expect(titles[start + 1], 'Health check');
      expect(titles.last, 'Stop the old color');
      expect(p.recovery.map((x) => x.title), contains('Flip the front back'));
    });

    test('rollback flips too', () {
      final p = planRollback(ctx: ctx, r: r, state: s);
      expect(p.steps.first.title, contains('(blue/green)'));
      expect(p.recovery.single.title, 'Flip the front back');
    });

    test('per-env database: in place, with the reason in the plan', () {
      final c2 = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '    database: {name: demo}\n',
          '    database: {name: demo}\n    switch: blue_green\n',
        ),
        root: '/work/demo',
      );
      final ctx2 = Ctx(config: c2, ssh: Ssh(), log: Log.silent(), dryRun: true);
      final p = planDeploy(
        ctx: ctx2,
        r: resolveEnv(c2, c2.env('production'), s.registry),
        state: s,
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 6, 16),
        snapshot: '/tmp/snap',
      );
      final titles = p.steps.map((x) => x.title).toList();
      expect(titles, contains('Switch mode: in place'));
      expect(titles, contains(startsWith('Switch to')));
    });
  });
}
