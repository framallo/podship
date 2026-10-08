@Tags(['unit'])
library;

import 'dart:io';

import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/release_ops.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const r1 = '20261001-000000-aaaaaaa',
    r2 = '20261002-000000-bbbbbbb',
    r3 = '20261003-000000-ccccccc';

EnvState stateWith({
  String? current,
  Map<String, String> releases = const {},
  bool db = true,
  String project = 'demo',
}) => parseState(
  [
    'CURRENT ${current ?? ''}',
    for (final e in releases.entries)
      'R ${e.key} ${e.value} {"id":"${e.key}","sha":"abc","images":["$project-server:${e.key}"]}',
    'ENVFILE yes',
    if (db) 'DB yes',
    'PORTS 22 8087 20000',
    'REGISTRY-BEGIN',
    'REGISTRY-END',
  ].join('\n'),
);

void main() {
  final config = PodshipConfig.parse(sampleConfig, root: '/work/demo');
  final ctx = Ctx(config: config, ssh: Ssh(), log: Log.silent(), dryRun: true);
  ResolvedEnv resolve(String env, EnvState s) =>
      resolveEnv(config, config.env(env), s.registry, listening: s.listening);

  group('parseState', () {
    test('reads current, releases, flags, ports and registry', () {
      final s = parseState(
        'CURRENT $r2\nR $r1 ok {"id":"$r1","sha":"x","images":[]}\nR $r2 failed {}\nENVFILE yes\nPORTS 22 80\nREGISTRY-BEGIN\nversion: 1\nREGISTRY-END\n',
      );
      expect(s.current, r2);
      expect(s.ids, [r1, r2]);
      expect(s.failed, {r2});
      expect(s.releases.first.meta!.sha, 'x');
      expect(s.envFileExists, isTrue);
      expect(s.dbRunning, isFalse);
      expect(s.listening, {22, 80});
      expect(s.registryText, contains('version: 1'));
    });
  });

  group('resolveEnv', () {
    test(
      'allocates auto ports around listening ones and fills placeholders',
      () {
        final s = stateWith();
        final r = resolve('staging', s);
        expect(r.ports.values, everyElement(greaterThanOrEqualTo(20001)));
        expect(r.healthUrl, 'http://127.0.0.1:${r.ports['web']}/health');
        expect(r.backupSchedule, '*-*-* 03:00:00');
      },
    );
    test('maps named route ports', () {
      final r = resolve('production', stateWith());
      expect(r.domains['demo.example.com']!.map((x) => x.port), [8086, 8087]);
      expect(r.healthUrl, 'http://127.0.0.1:8087/health');
    });
  });

  group('planDeploy', () {
    Plan plan(EnvState s, {DeployOptions options = const DeployOptions()}) =>
        planDeploy(
          ctx: ctx,
          r: resolve('production', s),
          state: s,
          git: GitInfo('a0dc2b0123456789', ref: 'main'),
          now: DateTime.utc(2026, 10, 6, 16, 0, 0),
          snapshot: '/tmp/snap',
          options: options,
        );

    test('runs the steps in order and guards the switch', () {
      final p = plan(stateWith(current: r2, releases: {r1: 'ok', r2: 'ok'}));
      final titles = p.steps.map((s) => s.title).toList();
      expect(titles, [
        'Export main (a0dc2b0)',
        'Build Flutter web: app',
        'Pre-deploy hook',
        'Select files and write release 20261006-160000-a0dc2b0',
        'Prepare prod-box:/srv/demo',
        'Upload files',
        'Create release 20261006-160000-a0dc2b0',
        'Build images on the server',
        'Put podship at /srv/podship/bin/podship on prod-box',
        'Back up the database before the switch',
        'Switch to 20261006-160000-a0dc2b0',
        'Health check',
        'Serverpod readiness (/readyz)',
        'Mark 20261006-160000-a0dc2b0 healthy and keep 5 releases',
      ]);
      expect(
        p.guards(titles.indexOf('Switch to 20261006-160000-a0dc2b0')),
        isTrue,
      );
      expect(p.guards(titles.indexOf('Health check')), isTrue);
      expect(p.guards(titles.length - 1), isFalse);
      expect(p.guards(titles.indexOf('Build images on the server')), isFalse);
      expect(p.recovery.map((s) => s.title), [
        'Mark 20261006-160000-a0dc2b0 failed',
        'Roll back to $r2',
        'Health check of $r2',
      ]);
    });

    test(
      'the build step pulls extra contexts and builds with the release compose',
      () {
        final p = plan(stateWith());
        final build = p.steps.whereType<RemoteStep>().firstWhere(
          (s) => s.title.startsWith('Build images'),
        );
        expect(build.script, contains('git -C /srv/worker pull --ff-only'));
        expect(
          build.script,
          contains(
            '/srv/demo/releases/20261006-160000-a0dc2b0/.podship/compose.sh build',
          ),
        );
      },
    );

    test('the first deploy has no rollback target and no backup', () {
      final p = plan(stateWith(db: false));
      expect(p.recovery.map((s) => s.title), [
        'Mark 20261006-160000-a0dc2b0 failed',
      ]);
      final backup = p.steps.whereType<RemoteStep>().firstWhere(
        (s) => s.title.startsWith('Back up'),
      );
      expect(backup.script, contains('no database running yet'));
    });

    test('skips web builds, hooks and the backup on request', () {
      final p = plan(
        stateWith(),
        options: const DeployOptions(
          skipWeb: true,
          skipHooks: true,
          skipBackup: true,
        ),
      );
      final titles = p.steps.map((s) => s.title);
      expect(titles, isNot(contains('Build Flutter web: app')));
      expect(titles, isNot(contains('Pre-deploy hook')));
      expect(titles.where((t) => t.startsWith('Back up')), isEmpty);
    });

    test('prunes beyond the kept releases but never the previous one', () {
      final many = {
        for (var i = 1; i <= 6; i++) '2026090$i-000000-abcdef$i': 'ok',
      };
      final p = plan(
        stateWith(current: '20260901-000000-abcdef1', releases: many),
      );
      final last = p.steps.last as RemoteStep;
      expect(
        last.script,
        isNot(contains('rm -rf -- /srv/demo/releases/20260901-000000-abcdef1')),
      );
      expect(
        last.script,
        contains('rm -rf -- /srv/demo/releases/20260902-000000-abcdef2'),
      );
    });

    test('the dry-run text names every step and holds no secret values', () {
      final text = plan(stateWith(current: r1, releases: {r1: 'ok'})).render();
      expect(text, contains('If a step from'));
      expect(text, isNot(contains('PASSWORD=')));
    });
  });

  group('planRollback', () {
    test('goes to the previous healthy release', () {
      final s = stateWith(
        current: r3,
        releases: {r1: 'ok', r2: 'failed', r3: 'ok'},
      );
      final p = planRollback(ctx: ctx, r: resolve('production', s), state: s);
      expect(p.title, contains('to $r1'));
      expect(p.steps.first.title, 'Switch to $r1');
      expect(p.recovery.first.title, 'Switch back to $r3');
    });
    test('restores a backup first with --with-db', () {
      final s = stateWith(current: r2, releases: {r1: 'ok', r2: 'ok'});
      final p = planRollback(
        ctx: ctx,
        r: resolve('production', s),
        state: s,
        withDb: '2026-10-06T0330',
      );
      final restore = p.steps.whereType<RemoteStep>().firstWhere(
        (x) => x.title.startsWith('Restore'),
      );
      expect(
        restore.script,
        contains(
          '/srv/podship/bin/podship agent restore --conf /srv/podship/etc/demo-backup.conf --confirmed demo 2026-10-06T0330',
        ),
      );
      expect(p.guardFrom, 2);
    });
    test('refuses unknown or current targets', () {
      final s = stateWith(current: r2, releases: {r1: 'ok', r2: 'ok'});
      expect(
        () => planRollback(
          ctx: ctx,
          r: resolve('production', s),
          state: s,
          to: r2,
        ),
        throwsA(isA<Aborted>()),
      );
      expect(
        () => planRollback(
          ctx: ctx,
          r: resolve('production', s),
          state: s,
          to: r3,
        ),
        throwsA(isA<Aborted>()),
      );
      final one = stateWith(current: r1, releases: {r1: 'ok'});
      expect(
        () => planRollback(ctx: ctx, r: resolve('production', one), state: one),
        throwsA(isA<Aborted>()),
      );
    });
  });

  group('planPromote', () {
    test(
      'copies files and retags images on the same host, then switches',
      () async {
        final from = stateWith(
          current: r2,
          releases: {r2: 'ok'},
          project: 'demo-staging',
        );
        final to = stateWith(current: r1, releases: {r1: 'ok'});
        final work = Directory.systemTemp.createTempSync('podship-plan-');
        addTearDown(() => work.deleteSync(recursive: true));
        final p = await planPromote(
          ctx: ctx,
          from: config.env('staging'),
          fromState: from,
          to: resolve('production', to),
          toState: to,
          release: r2,
          workDir: work.path,
        );
        final copy = p.steps.whereType<RemoteStep>().first;
        expect(
          copy.script,
          contains('docker tag demo-staging-server:$r2 demo-server:$r2'),
        );
        expect(p.steps.map((s) => s.title), contains('Switch to $r2'));
        expect(
          p.steps.map((s) => s.title).where((t) => t.startsWith('Build')),
          isEmpty,
        );
      },
    );
    test('refuses a failed release', () async {
      final from = stateWith(current: r2, releases: {r2: 'failed'});
      expect(
        () => planPromote(
          ctx: ctx,
          from: config.env('staging'),
          fromState: from,
          to: resolve('production', stateWith()),
          toState: stateWith(),
          release: r2,
          workDir: '/tmp',
        ),
        throwsA(isA<Aborted>()),
      );
    });
  });
}
