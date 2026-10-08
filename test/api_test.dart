@Tags(['unit'])
library;

import 'dart:convert';

import 'package:podship/podship.dart';
import 'package:podship/src/ops/state.dart';
import 'package:test/test.dart';

void main() {
  group('events', () {
    test('every event has a type, a time and JSON fields', () {
      final events = <PodshipEvent>[
        OperationStarted('deploy', project: 'p', env: 'staging', host: 'h'),
        PlanReady('t', ['a'], 'text'),
        StepStarted(1, 2, 'a'),
        StepFinished(1, 'a', const Duration(milliseconds: 1500)),
        StepFailed(2, 'b', 'boom'),
        LogLine('hello', level: LogLevel.warn),
        OperationFinished(
          OperationResult(
            operation: 'deploy',
            ok: true,
            duration: const Duration(seconds: 3),
            release: 'R',
          ),
        ),
      ];
      for (final e in events) {
        final j = jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>;
        expect(j['type'], e.type);
        expect(j['time'], isA<String>());
      }
      expect(events.last.toJson()['release'], 'R');
      expect(events.last.toJson()['duration_ms'], 3000);
    });

    test('render text for the terminal', () {
      expect(renderEventText(StepStarted(1, 3, 'Build')), '▶ 1/3 Build');
      expect(
        renderEventText(StepStarted(1, 2, 'Undo', recovery: true)),
        '↺ Undo',
      );
      expect(renderEventText(LogLine('x', level: LogLevel.detail)), isNull);
      expect(
        renderEventText(LogLine('x', level: LogLevel.detail), verbose: true),
        '  x',
      );
      expect(
        renderEventText(
          OperationFinished(
            OperationResult(
              operation: 'deploy',
              ok: false,
              duration: Duration.zero,
              error: 'no',
            ),
          ),
        ),
        '✗ deploy failed: no',
      );
      expect(
        renderEventText(
          OperationFinished(
            OperationResult(
              operation: 'deploy',
              ok: true,
              env: 'staging',
              release: 'R',
              duration: const Duration(seconds: 2),
            ),
          ),
        ),
        '✓ deploy staging (R): done in 2.0 s',
      );
    });

    test('a result keeps its history path', () {
      final r = OperationResult(
        operation: 'x',
        ok: true,
        duration: Duration.zero,
      ).withHistory('/h.json');
      expect(r.toJson()['history'], '/h.json');
    });
  });

  group('models', () {
    test('EnvStatus reads compose ps JSON, health and disk', () {
      final state = parseState(
        'CURRENT R2\nR R1 ok {}\nR R2 ok {}\nREGISTRY-BEGIN\nREGISTRY-END\n',
      );
      final s = EnvStatus.parse(
        project: 'p',
        env: 'staging',
        host: 'h',
        dir: '/d',
        state: state,
        ports: {'web': 1},
        healthUrl: 'u',
        output:
            'PS {"Service":"server","Name":"p-server-1","State":"running","Status":"Up 2 minutes","Publishers":[{"URL":"127.0.0.1","TargetPort":8082,"PublishedPort":20001}]}\n'
            'HEALTH ok\nDISK 1048576 2097152\nRELEASES_KB 100\n',
      );
      expect(s.healthy, isTrue);
      expect(s.containers.single.ports, '127.0.0.1:20001->8082');
      expect(s.releases.first.id, 'R2');
      final j = s.toJson();
      expect((j['releases'] as List).first, containsPair('current', true));
      expect(j['disk_free_kb'], 1048576);
    });

    test('MigrationStatus compares the project module', () {
      final m = MigrationStatus.parse(
        'shop | 20261004 | t\nserverpod | 1 | t\n',
        '20261005',
        'shop_server',
      );
      expect(m.appliedVersion, '20261004');
      expect(m.state, 'pending');
      expect(
        MigrationStatus.parse('shop | 2 | t', '2', 'shop_server').state,
        'up_to_date',
      );
      expect(MigrationStatus.parse('', '', 'shop_server').state, 'unknown');
    });

    test('BackupInfo and EnvVarInfo', () {
      final b = BackupInfo.parse('2026-10-06T1128 1.5M yes');
      expect(b.toJson(), {
        'stamp': '2026-10-06T1128',
        'size': '1.5M',
        'encrypted': true,
      });
      expect(EnvVarInfo('K', secret: true).toJson(), {
        'name': 'K',
        'secret': true,
      });
    });

    test('HistoryRecord fields', () {
      final r = HistoryRecord({
        'operation': 'deploy',
        'ok': true,
        'release': 'R',
        'started_at': 'T',
        'project': 'p',
        'env': 'e',
      });
      expect(r.ok, isTrue);
      expect(r.release, 'R');
    });
  });
}
