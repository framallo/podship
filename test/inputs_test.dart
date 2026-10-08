@Tags(['unit'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/podship.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/inputs.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/ops/tests.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const r1 = '20261001-000000-aaaaaaa', r2 = '20261002-000000-bbbbbbb';

EnvState state({
  String? current,
  Map<String, Map<String, Object?>> releases = const {},
}) => parseState(
  [
    'CURRENT ${current ?? ''}',
    for (final e in releases.entries)
      'R ${e.key} ${e.value['status'] ?? 'ok'} {"id":"${e.key}","sha":"abc","images":[]'
          '${e.value['web'] == null ? '' : ',"web":${_json(e.value['web'] as Map)}'}}',
    'ENVFILE yes',
    'DB yes',
    'PORTS 22',
    'REGISTRY-BEGIN',
    'REGISTRY-END',
  ].join('\n'),
);

String _json(Map m) =>
    '{${m.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}';

Future<void> git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

void main() {
  group('pathDependencies', () {
    test('resolves path: entries against the package folder', () {
      const pubspec = '''
name: demo_flutter
dependencies:
  demo_client:
    path: ../demo_client
  demo_ui:
    git:
      url: https://example.com/ui.git
      path: demo_ui
  http: ^1.0.0
dev_dependencies:
  demo_test_utils: {path: ../tools/test_utils}
dependency_overrides:
  outside: {path: ../../elsewhere}
''';
      expect(pathDependencies(pubspec, 'demo_flutter'), [
        'demo_client',
        'tools/test_utils',
      ]);
    });
    test('ignores broken YAML', () {
      expect(pathDependencies(': : :', 'x'), isEmpty);
    });
  });

  group('inputsHash', () {
    late Directory repo;
    late String sha1, sha2, sha3;

    setUpAll(() async {
      repo = await Directory.systemTemp.createTemp('podship-inputs-');
      final d = repo.path;
      await git(d, ['init', '-q', '-b', 'main']);
      await git(d, ['config', 'user.email', 't@example.com']);
      await git(d, ['config', 'user.name', 't']);
      Directory(p.join(d, 'app/lib')).createSync(recursive: true);
      Directory(p.join(d, 'client/lib')).createSync(recursive: true);
      File(p.join(d, 'pubspec.lock')).writeAsStringSync('packages: {}\n');
      File(p.join(d, 'app/pubspec.yaml')).writeAsStringSync(
        'name: app\ndependencies:\n  client: {path: ../client}\n',
      );
      File(
        p.join(d, 'app/lib/main.dart'),
      ).writeAsStringSync('void main() {}\n');
      File(p.join(d, 'client/lib/c.dart')).writeAsStringSync('class C {}\n');
      File(p.join(d, 'server/README')).createSync(recursive: true);
      await git(d, ['add', '.']);
      await git(d, ['commit', '-q', '-m', 'one']);
      sha1 = (await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: d)).stdout.toString().trim();
      // A change outside the app's inputs.
      File(p.join(d, 'server/README')).writeAsStringSync('v2\n');
      await git(d, ['commit', '-q', '-am', 'two']);
      sha2 = (await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: d)).stdout.toString().trim();
      // A change in a path dependency.
      File(
        p.join(d, 'client/lib/c.dart'),
      ).writeAsStringSync('class C { int x = 1; }\n');
      await git(d, ['commit', '-q', '-am', 'three']);
      sha3 = (await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: d)).stdout.toString().trim();
    });

    tearDownAll(() => repo.delete(recursive: true));

    test(
      'the inputs of a package are its folder, path deps and the lock',
      () async {
        expect(await packageInputs(repo.path, sha1, 'app'), [
          'app',
          'client',
          'pubspec.lock',
        ]);
        expect(await packageInputs(repo.path, sha1, 'app', extra: ['server']), [
          'app',
          'client',
          'pubspec.lock',
          'server',
        ]);
      },
    );

    test(
      'the hash is stable across unrelated commits and changes with a dependency',
      () async {
        final paths = await packageInputs(repo.path, sha1, 'app');
        final h1 = await inputsHash(
          repo.path,
          sha1,
          paths,
          salt: ['flutter 3'],
        );
        final h2 = await inputsHash(
          repo.path,
          sha2,
          paths,
          salt: ['flutter 3'],
        );
        final h3 = await inputsHash(
          repo.path,
          sha3,
          paths,
          salt: ['flutter 3'],
        );
        expect(h1, isNotNull);
        expect(h1, h2);
        expect(h3, isNot(h1));
        expect(
          await inputsHash(repo.path, sha1, paths, salt: ['flutter 4']),
          isNot(h1),
        );
      },
    );

    test('no hash outside git or for a missing path', () async {
      expect(await inputsHash(repo.path, 'nogit', ['app']), isNull);
      expect(await inputsHash(repo.path, sha1, ['app', 'missing']), isNull);
    });
  });

  group('planDeploy with inputs', () {
    final config = PodshipConfig.parse(sampleConfig, root: '/work/demo');
    final ctx = Ctx(
      config: config,
      ssh: Ssh(),
      log: Log.silent(),
      dryRun: true,
    );
    Plan plan(EnvState s, DeployInputs inputs) => planDeploy(
      ctx: ctx,
      r: resolveEnv(
        config,
        config.env('production'),
        s.registry,
        listening: s.listening,
      ),
      state: s,
      git: GitInfo('a0dc2b0123456789', ref: 'main'),
      now: DateTime.utc(2026, 10, 6, 16, 0, 0),
      snapshot: '/tmp/snap',
      options: DeployOptions(inputs: inputs),
    );

    test('an app with the hash of a kept release is linked, not built', () {
      final s = state(
        current: r2,
        releases: {
          r1: {
            'web': {'app': 'h1'},
          },
          r2: {
            'web': {'app': 'h1'},
          },
        },
      );
      final inputs = DeployInputs(
        webHashes: {'app': 'h1'},
        webReuse: {'app': r2},
      );
      final pl = plan(s, inputs);
      final titles = pl.steps.map((x) => x.title).toList();
      expect(titles, contains('Reuse Flutter web: app'));
      expect(titles, isNot(contains('Build Flutter web: app')));
      final create = pl.steps.whereType<RemoteStep>().firstWhere(
        (x) => x.title.startsWith('Create release'),
      );
      expect(
        create.script,
        contains('_cplink /srv/demo/releases/$r2/demo_server/web/app'),
      );
      expect(
        create.script,
        contains('reused demo_server/web/app from release $r2'),
      );
      // The reuse is linked into the temporary folder before the rename.
      expect(
        create.script.indexOf('_cplink /srv/demo/releases/$r2'),
        lessThan(
          create.script.indexOf(
            'mv /srv/demo/releases/20261006-160000-a0dc2b0.podship-tmp',
          ),
        ),
      );
    });

    test(
      'without a match the app is built and the release carries its hash',
      () {
        final pl = plan(
          state(current: r1),
          DeployInputs(webHashes: {'app': 'h9'}),
        );
        final titles = pl.steps.map((x) => x.title).toList();
        expect(titles, contains('Build Flutter web: app'));
        final create = pl.steps.whereType<RemoteStep>().firstWhere(
          (x) => x.title.startsWith('Create release'),
        );
        expect(create.script, isNot(contains('reused')));
      },
    );

    test('--skip-web never reuses', () {
      final pl = planDeploy(
        ctx: ctx,
        r: resolveEnv(
          config,
          config.env('production'),
          state().registry,
          listening: const {},
        ),
        state: state(),
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 6, 16, 0, 0),
        snapshot: '/tmp/snap',
        options: DeployOptions(
          skipWeb: true,
          inputs: DeployInputs(webHashes: {'app': 'h1'}, webReuse: {'app': r1}),
        ),
      );
      final titles = pl.steps.map((x) => x.title).toList();
      expect(titles, isNot(contains('Reuse Flutter web: app')));
      expect(titles, isNot(contains('Build Flutter web: app')));
    });
  });

  group('ReleaseMeta', () {
    test('keeps the web hashes', () {
      final m = ReleaseMeta.fromJson({
        'id': r1,
        'sha': 'abc',
        'images': [],
        'web': {'app': 'h1', 'admin': 'h2'},
      });
      expect(m.web, {'app': 'h1', 'admin': 'h2'});
      expect(m.toJson()['web'], {'app': 'h1', 'admin': 'h2'});
      expect(
        ReleaseMeta.fromJson({'id': r1}).toJson().containsKey('web'),
        isFalse,
      );
    });
  });

  group('test stage', () {
    test(
      'unchanged suites are skipped and reported; the others run in parallel',
      () async {
        final events = <PodshipEvent>[];
        final config = PodshipConfig.parse(sampleConfig, root: '/work/demo');
        final ctx = Ctx(
          config: config,
          ssh: Ssh(),
          log: Log((e) => events.add(e)),
        );
        final dir = await Directory.systemTemp.createTemp('podship-suites-');
        addTearDown(() => dir.delete(recursive: true));
        final suites = [
          TestSuite(
            name: 'a',
            dir: '.',
            command: 'sleep 0.3; echo "00:01 +3: All tests passed!"',
          ),
          TestSuite(
            name: 'b',
            dir: '.',
            command: 'sleep 0.3; echo "00:01 +2: All tests passed!"',
          ),
          TestSuite(name: 'c', dir: '.', command: 'exit 1'),
        ];
        final plan = SuitePlan(
          hashes: {'a': 'ha', 'b': 'hb', 'c': 'hc'},
          prior: {
            'c': PriorPass(
              sha: 'abc1234567',
              env: 'staging',
              at: 't',
              passed: 7,
            ),
          },
        );
        final watch = Stopwatch()..start();
        final results = await runSuitesLocally(
          ctx,
          suites,
          dir.path,
          p.join(dir.path, 'logs'),
          plan: plan,
        );
        // Two 0.3 s suites side by side take well under 0.6 s.
        expect(watch.elapsed, lessThan(const Duration(milliseconds: 550)));
        expect(results.map((r) => r.suite), ['a', 'b', 'c']);
        expect(results.every((r) => r.ok), isTrue);
        expect(results[0].inputsHash, 'ha');
        expect(results[0].passed, 3);
        final c = results[2];
        expect(c.unchanged, isTrue);
        expect(c.sameAs, 'abc1234567');
        expect(c.passed, 7);
        expect(c.toJson()['same_as'], 'abc1234567');
        expect(
          renderEventText(SuiteFinished(c)),
          '✓ tests c: unchanged since abc1234, skipped (7 passed then)',
        );
        expect(events.whereType<SuiteStarted>().map((e) => e.suite), [
          'a',
          'b',
        ]);
        expect(events.whereType<SuiteFinished>(), hasLength(3));
      },
    );

    test('sequential when parallel is off', () async {
      final config = PodshipConfig.parse(sampleConfig, root: '/work/demo');
      final ctx = Ctx(config: config, ssh: Ssh(), log: Log.silent());
      final dir = await Directory.systemTemp.createTemp('podship-suites-');
      addTearDown(() => dir.delete(recursive: true));
      final watch = Stopwatch()..start();
      await runSuitesLocally(
        ctx,
        [
          TestSuite(name: 'a', dir: '.', command: 'sleep 0.3'),
          TestSuite(name: 'b', dir: '.', command: 'sleep 0.3'),
        ],
        dir.path,
        p.join(dir.path, 'logs'),
        parallel: false,
      );
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 550)));
    });

    test('config: parallel, inputs and skip_unchanged', () {
      final c = PodshipConfig.parse(
        '$sampleConfig\n'
        'tests:\n'
        '  parallel: false\n'
        '  suites:\n'
        '    - {name: s, dir: demo_server, command: dart test, inputs: [shared], skip_unchanged: false}\n',
      );
      expect(c.tests.parallel, isFalse);
      expect(c.tests.suites.single.inputs, ['shared']);
      expect(c.tests.suites.single.skipUnchanged, isFalse);
      expect(PodshipConfig.parse(sampleConfig).tests.parallel, isTrue);
      expect(
        PodshipConfig.parse(sampleConfig).build.flutterWeb.single.reuse,
        isTrue,
      );
    });
  });
}
