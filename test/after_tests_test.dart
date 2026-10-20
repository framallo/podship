// REV-18 (podship#1): suites with `blocks: false` do not gate a deploy. They
// run after the switch, their results are recorded apart, and a failure
// notifies and opens an issue instead of rolling back.
@Tags(['unit'])
library;

import 'package:podship/podship.dart';
import 'package:podship/src/ops/after_tests.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const _withSuites =
    '$sampleConfig\n'
    'tests:\n'
    '  suites:\n'
    '    - {name: server, dir: demo_server, command: dart test}\n'
    '    - {name: ui, dir: demo_ui, command: flutter test, blocks: false}\n'
    '    - {name: tool, dir: tool, command: dart test, blocks: false, environments: [staging]}\n';

const _r1 = '20261001-000000-aaaaaaa';

EnvState _state() => parseState(
  [
    'CURRENT $_r1',
    'R $_r1 ok {"id":"$_r1","sha":"abc","images":[]}',
    'ENVFILE yes',
    'DB yes',
    'PORTS 22',
    'REGISTRY-BEGIN',
    'REGISTRY-END',
  ].join('\n'),
);

void main() {
  planTests();
  reportTests();
  group('blocks: false', () {
    test(
      'a suite blocks by default; blocks: false puts it after the deploy',
      () {
        final c = PodshipConfig.parse(_withSuites);
        expect(c.tests.suites.map((s) => s.blocks), [true, false, false]);
        expect(c.tests.forEnv('production').map((s) => s.name), ['server']);
        expect(c.tests.afterFor('production').map((s) => s.name), ['ui']);
        expect(c.tests.afterFor('staging').map((s) => s.name), ['ui', 'tool']);
        expect(c.tests.allFor('production').map((s) => s.name), [
          'server',
          'ui',
        ]);
      },
    );

    test('blocks must be a boolean', () {
      expect(
        () => PodshipConfig.parse(
          '$sampleConfig\ntests:\n  suites:\n'
          '    - {name: s, dir: demo_server, command: dart test, blocks: later}\n',
        ),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}

void planTests() {
  group('the deploy plan', () {
    final config = PodshipConfig.parse(_withSuites, root: '/work/demo');
    Plan plan(PodshipConfig c) => planDeploy(
      ctx: Ctx(config: c, ssh: Ssh(), log: Log.silent(), dryRun: true),
      r: resolveEnv(
        c,
        c.env('production'),
        _state().registry,
        listening: _state().listening,
      ),
      state: _state(),
      git: GitInfo('a0dc2b0123456789', ref: 'main'),
      now: DateTime.utc(2026, 10, 19, 12, 0, 0),
      snapshot: '/tmp/snap',
      options: const DeployOptions(),
    );

    test('after suites are the last step, outside the rollback guard', () {
      final pl = plan(config);
      final titles = pl.steps.map((s) => s.title).toList();
      expect(titles.first, startsWith('Export'));
      expect(titles, contains('Run tests (server)'));
      expect(titles.last, 'Run tests after deploy (ui)');
      expect(pl.guards(pl.steps.length - 1), isFalse);
      expect(pl.steps.last.describe(), contains('never rolls back'));
    });

    test('no after suites, no step', () {
      final pl = plan(PodshipConfig.parse(sampleConfig, root: '/work/demo'));
      expect(
        pl.steps.map((s) => s.title),
        isNot(contains(startsWith('Run tests after deploy'))),
      );
    });
  });
}

void reportTests() {
  group('the report of the after-deploy suites', () {
    SuiteResult r(String name, {bool ok = true, int failed = 0}) => SuiteResult(
      suite: name,
      ok: ok,
      duration: const Duration(seconds: 12),
      passed: 40,
      failed: failed,
      failures: failed == 0 ? const [] : ['widget renders', 'theme dark'],
      exitCode: ok ? 0 : 1,
    );

    test('after_tests_failed is a notify event, on by default', () {
      expect(
        NotifyEvent.parse('after_tests_failed'),
        NotifyEvent.afterTestsFailed,
      );
      expect(NotifyEvent.defaults, contains(NotifyEvent.afterTestsFailed));
    });

    test('all suites passed: nothing to send, nothing to open', () {
      final rep = afterTestsReport(
        AfterTestsOutcome(
          results: [r('ui'), r('tool')],
          release: '20261019-120000-a0dc2b0',
        ),
        project: 'demo',
        env: 'production',
        sha: 'a0dc2b0123456789',
      );
      expect(rep.data['ok'], isTrue);
      expect(rep.data['issues'], isEmpty);
      expect(rep.notification, isNull);
      expect(rep.issues, isEmpty);
    });

    test('a failed suite: one notification, one issue per failed suite', () {
      final rep = afterTestsReport(
        AfterTestsOutcome(
          results: [
            r('ui', ok: false, failed: 2),
            r('tool'),
            r('book', ok: false, failed: 1),
          ],
          release: '20261019-120000-a0dc2b0',
          recordPath: '/srv/h/tests/a0dc2b0.after.json',
        ),
        project: 'demo',
        env: 'production',
        sha: 'a0dc2b0123456789',
      );
      expect(rep.data['ok'], isFalse);
      expect(rep.data['record'], '/srv/h/tests/a0dc2b0.after.json');
      final n = rep.notification!;
      expect(n.event, NotifyEvent.afterTestsFailed);
      expect(n.ok, isFalse);
      expect(n.title, 'tests after deploy FAILED (demo/production): ui, book');
      expect(n.body, contains('release 20261019-120000-a0dc2b0 stays'));
      expect(n.body, contains('ui: 2 failed'));
      expect(n.release, '20261019-120000-a0dc2b0');
      expect(rep.issues.map((i) => i.title), [
        'Tests after deploy: ui failed on production (20261019-120000-a0dc2b0)',
        'Tests after deploy: book failed on production (20261019-120000-a0dc2b0)',
      ]);
      final body = rep.issues.first.body;
      expect(body, contains('a0dc2b0'));
      expect(body, contains('widget renders'));
      expect(body, contains('2 failed'));
      expect(body, isNot(contains('null')));
    });

    test('the suites could not run: a notification, no issue', () {
      final rep = afterTestsReport(
        AfterTestsOutcome(
          results: const [],
          release: '20261019-120000-a0dc2b0',
          error: 'bash: flutter: command not found',
        ),
        project: 'demo',
        env: 'production',
        sha: 'a0dc2b0123456789',
      );
      expect(rep.notification!.title, contains('did not run'));
      expect(rep.notification!.body, contains('command not found'));
      expect(rep.issues, isEmpty);
      expect(rep.data['ok'], isFalse);
      expect(rep.data['error'], contains('not found'));
    });
  });
}
