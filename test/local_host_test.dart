@Tags(['unit'])
library;

import 'dart:io';

import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/backup_ops.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/release_ops.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/scheduler/agent.dart';
import 'package:podship/src/util/log.dart';
import 'package:podship/src/util/temp.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const _postSwitch = '''
    remote_post_switch:
      - ops/designer/install.sh
''';

void main() {
  group('host: local', () {
    test('scripts run with the local bash, not ssh', () async {
      final ssh = Ssh();
      final (exe, args) = ssh.command(localHost, 'echo hi');
      expect(exe, 'bash');
      expect(args, ['-c', 'echo hi']);
      expect(await ssh.capture(localHost, r'echo "$((1 + 1))"'), '2\n');
      final r = await ssh.captureResult(
        localHost,
        'cat; exit 3',
        stdin: [104, 105],
      );
      expect(r.exitCode, 3);
      expect(r.stdout, 'hi');
    });

    test('other hosts still go through ssh', () {
      final (exe, args) = Ssh().command('prod-box', 'echo hi');
      expect(exe, 'ssh');
      expect(args, containsAllInOrder(['prod-box', "bash -c 'echo hi'"]));
      expect(remoteSpec('prod-box', '/srv/x'), 'prod-box:/srv/x');
      expect(remoteSpec(localHost, '/srv/x'), '/srv/x');
    });

    test('an upload is a local rsync into the folder', () async {
      final tmp = await Directory.systemTemp.createTemp('podship-local-');
      addTearDown(() => tmp.delete(recursive: true));
      final src = Directory('${tmp.path}/src')..createSync();
      File('${src.path}/a.txt').writeAsStringSync('A');
      final code = await Ssh().upload(
        localHost,
        src.path,
        '${tmp.path}/dst',
        onLine: (_, _) {},
      );
      expect(code, 0);
      expect(File('${tmp.path}/dst/a.txt').readAsStringSync(), 'A');
    });

    test('the config accepts host: local', () {
      final config = PodshipConfig.parse(
        sampleConfig.replaceFirst('host: prod-box', 'host: local'),
        root: '/work/demo',
      );
      expect(isLocalHost(config.env('production').host), isTrue);
    });
  });

  group('remote_post_switch', () {
    final config = PodshipConfig.parse(
      sampleConfig.replaceFirst(
        '    dir: /srv/demo\n',
        '    dir: /srv/demo\n$_postSwitch',
      ),
      root: '/work/demo',
    );
    final ctx = Ctx(
      config: config,
      ssh: Ssh(),
      log: Log.silent(),
      dryRun: true,
    );
    final state = parseState(
      'CURRENT \nENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
    );
    Plan plan({bool skipHooks = false}) => planDeploy(
      ctx: ctx,
      r: resolveEnv(config, config.env('production'), state.registry),
      state: state,
      git: GitInfo('a0dc2b0123456789', ref: 'main'),
      now: DateTime.utc(2026, 10, 7, 18),
      snapshot: '/tmp/snap',
      options: DeployOptions(skipHooks: skipHooks),
    );

    test('runs in the new release after the health checks, guarded', () {
      final p = plan();
      final titles = p.steps.map((s) => s.title).toList();
      final i = titles.indexOf(
        'Run the post-switch commands in 20261007-180000-a0dc2b0',
      );
      expect(i, greaterThan(titles.indexOf('Health check')));
      expect(titles[i + 1], startsWith('Mark 20261007-180000-a0dc2b0 healthy'));
      expect(p.guards(i), isTrue, reason: 'a failure rolls back');
      final step = p.steps[i] as RemoteStep;
      expect(
        step.script,
        contains(
          'cd /srv/demo/releases/20261007-180000-a0dc2b0\nops/designer/install.sh',
        ),
      );
    });

    test(
      '--skip-hooks leaves them out; environments without them have none',
      () {
        expect(
          plan(skipHooks: true).steps.map((s) => s.title),
          isNot(contains(startsWith('Run the post-switch'))),
        );
        final plain = PodshipConfig.parse(sampleConfig, root: '/work/demo');
        expect(plain.env('production').remotePostSwitch, isNull);
        expect(plain.compose.remotePostSwitch, isEmpty);
      },
    );
  });

  test(
    'backup schedule writes the registry only: no launchctl, no systemctl',
    () {
      final config = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '      unit: demo-backup\n',
          '      unit: demo-backup\n      replaces: [io.example.old-backup]\n',
        ),
        root: '/work/demo',
      );
      final ctx = Ctx(
        config: config,
        ssh: Ssh(),
        log: Log.silent(),
        dryRun: true,
      );
      final state = parseState(
        'CURRENT \nENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
      );
      final reg = state.registry;
      final p = planSchedule(
        ctx,
        resolveEnv(config, config.env('production'), reg),
        registry: reg,
        registryText: state.registryText,
      );
      final text = p.render();
      expect(text, isNot(contains('launchctl')));
      expect(text, isNot(contains('systemctl')));
      expect(reg.jobs.keys, ['backup:demo/production']);
      final job = reg.jobs['backup:demo/production']!;
      expect(job.conf, '/srv/podship/etc/demo-backup.conf');
      expect(job.script, isNull);
      final write = p.steps.whereType<RemoteStep>().last.script;
      expect(write, contains('"backup:demo/production":'));
      expect(write, contains('/srv/podship/registry.yaml'));
      // The old unit in backup.replaces is retired by `scheduler install`.
      final retire = retireLegacyScript(
        const [],
        replaces: ['io.example.old-backup'],
        macos: true,
      );
      expect(
        retire,
        contains('launchctl bootout gui/\$(id -u)/io.example.old-backup'),
      );
      expect(retire, contains('.disabled-by-podship'));
    },
  );

  test('adopt names the release after a given commit (adopt --sha)', () {
    final config = PodshipConfig.parse(sampleConfig, root: '/work/demo');
    final ctx = Ctx(
      config: config,
      ssh: Ssh(),
      log: Log.silent(),
      dryRun: true,
    );
    final state = parseState(
      'CURRENT \nENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
    );
    final p = planAdopt(
      ctx: ctx,
      r: resolveEnv(config, config.env('production'), state.registry),
      state: state,
      scan: AdoptScan(
        'b9913c6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        {'server': 'sha256:1'},
        {'docker-compose.yml': 'services:\n  server:\n    build: .\n'},
      ),
      composeDir: '/srv/demo',
      now: DateTime.utc(2026, 10, 7, 18),
      workDir: '/tmp/x',
    );
    expect(p.title, endsWith('20261007-180000-b9913c6-adopted'));
  });

  test('backup pull checks the newest podship stamp, not other archives', () {
    final script = verifyNewestScript('/b', ['/k']);
    expect(
      script,
      contains('/b/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*.tar.age'),
    );
    expect(script, isNot(contains('/b/*.tar.age 2>/dev/null | sort')));
  });

  test('release exports live under /tmp, so socket paths stay short', () async {
    final d = await createExportDir('podship-release-');
    addTearDown(() => d.delete(recursive: true));
    if (!Platform.isWindows) {
      expect(d.path, startsWith('/tmp/podship-release-'));
    }
    // A Postgres socket inside a server package still fits in 104 bytes.
    final socket = '${d.path}/shop_server/.serverpod/test/pgdata/.s.PGSQL.5432';
    expect(socket.length, lessThan(104));
  });
}
