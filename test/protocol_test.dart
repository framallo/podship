@Tags(['unit'])
library;

import 'dart:convert';

import 'package:podship/podship.dart';
import 'package:podship/src/ops/tests.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('test output', () {
    test('reads counts and failed tests from the expanded reporter', () {
      const out =
          '00:01 +1: a passes\n'
          '00:02 +1 -1: group b fails [E]\n'
          '  Expected: 1\n'
          '00:03 +5 ~2 -1: Some tests failed.\n';
      final r = parseTestOutput(out);
      expect(r.passed, 5);
      expect(r.skipped, 2);
      expect(r.failed, 1);
      expect(r.failures, ['group b fails']);
    });
    test('strips colors', () {
      final r = parseTestOutput(
        '00:05 \x1B[32m+188\x1B[0m: All tests passed!\n',
      );
      expect(r.passed, 188);
      expect(r.failed, 0);
    });
  });

  group('protocol', () {
    test('every operation has a unique stable name and a JSON schema', () {
      final names = operations.map((o) => o.name).toList();
      expect(names.toSet(), hasLength(names.length));
      for (final o in operations) {
        final schema = o.inputSchema();
        expect(schema['type'], 'object');
        expect(jsonEncode(schema), isNotEmpty);
        if (o.confirmation != null) {
          expect((schema['properties'] as Map).keys, contains(o.confirmation));
        }
      }
      expect(operationSpec('deploy')!.destructive, isTrue);
      expect(operationSpec('status')!.mutating, isFalse);
    });

    test('requests round-trip through JSON', () {
      final r = OperationRequest(
        operation: 'deploy',
        project: 'demo',
        env: 'staging',
        params: {'ref': 'main'},
      );
      final back = OperationRequest.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>,
      );
      expect(back.id, r.id);
      expect(back.params, {'ref': 'main'});
      expect(back.protocol, protocolVersion);
    });

    test('events round-trip through JSON', () {
      final events = <PodshipEvent>[
        StepStarted(2, 5, 'Build'),
        LogLine('x', level: LogLevel.warn),
        SuiteFinished(
          SuiteResult(
            suite: 'server',
            ok: true,
            duration: const Duration(seconds: 3),
            passed: 9,
          ),
        ),
        OperationFinished(
          OperationResult(
            operation: 'deploy',
            ok: true,
            duration: const Duration(seconds: 1),
            release: 'R',
            data: {'sha': 'abc'},
          ),
        ),
      ];
      for (final e in events) {
        final back = eventFromJson(
          jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>,
        );
        expect(back.toJson()..remove('time'), e.toJson()..remove('time'));
      }
    });

    test('a library operation carries its request and starts lazily', () {
      final podship = Podship(PodshipConfig.parse(sampleConfig), dryRun: true);
      final op = podship.deploy('staging', skipTestsReason: 'hotfix');
      expect(op.request.operation, 'deploy');
      expect(op.request.env, 'staging');
      expect(op.request.params['skip_tests_reason'], 'hotfix');
      expect(op.request.dryRun, isTrue);
      expect(podship.backupNow('production').request.operation, 'backup.now');
    });

    test(
      'dispatch refuses unknown operations, environments and projects',
      () async {
        final podship = Podship(PodshipConfig.parse(sampleConfig));
        Future<Map<String, Object?>> last(OperationRequest r) async =>
            (await dispatch(podship, r).toList()).last;
        expect(
          (await last(
            OperationRequest(
              operation: 'nope',
              project: 'demo',
              env: 'staging',
            ),
          ))['error'],
          contains('unknown operation'),
        );
        expect(
          (await last(
            OperationRequest(operation: 'status', project: 'demo', env: 'qa'),
          ))['error'],
          contains('unknown environment'),
        );
        expect(
          (await last(
            OperationRequest(
              operation: 'status',
              project: 'other',
              env: 'staging',
            ),
          ))['error'],
          contains('not demo'),
        );
        expect(
          (await last(
            OperationRequest(
              operation: 'destroy',
              project: 'demo',
              env: 'staging',
              params: {'confirm_project': 'x'},
            ),
          ))['error'],
          contains('confirm_project'),
        );
        expect(
          (await last(
            OperationRequest(
              operation: 'status',
              project: 'demo',
              protocol: 99,
              env: 'staging',
            ),
          ))['error'],
          contains('newer'),
        );
      },
    );
  });

  group('tests config', () {
    test('suites per environment and the gate', () {
      final c = PodshipConfig.parse('''
$sampleConfig
tests:
  suites:
    - {name: server, dir: demo_server, command: run-server-tests, environments: [staging]}
    - {name: all, command: run-all}
''');
      expect(c.tests.gate, ['production']);
      expect(c.tests.forEnv('staging').map((s) => s.name), ['server', 'all']);
      expect(c.tests.forEnv('production').map((s) => s.name), ['all']);
      expect(c.tests.suites.first.timeoutSeconds, 1800);
    });
    test('refuses an unknown environment in a suite', () {
      expect(
        () => PodshipConfig.parse(
          '$sampleConfig\ntests:\n  suites:\n    - {name: x, command: y, environments: [qa]}\n',
        ),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
