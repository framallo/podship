@Tags(['unit'])
library;

import 'dart:convert';

import 'package:podship/src/api/events.dart';
import 'package:podship/src/api/github.dart';
import 'package:podship/src/config/config.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

const _yaml = '''
project: demo
github:
  repo: owner/demo
environments:
  staging:
    host: box
    dir: /srv/demo
    ports: {web: 8087}
    health: {url: "http://127.0.0.1:{port:web}/health"}
    domains:
      - host: staging.example.com
        routes: [{port: web}]
''';

void main() {
  late List<(List<String>, Map<String, Object?>?)> calls;
  late List<LogLine> lines;
  late GitHub gh;
  late EnvConfig env;

  setUp(() {
    calls = [];
    lines = [];
    final config = PodshipConfig.parse(_yaml);
    env = config.env('staging');
    gh = GitHub(
      config,
      Log((e) => lines.add(e as LogLine)),
      runGh: (args, {input}) async {
        calls.add((
          args,
          input == null ? null : jsonDecode(input) as Map<String, Object?>,
        ));
        return args[1].endsWith('/deployments') ? '{"id": 42}' : '{}';
      },
    );
  });

  group('deployment status', () {
    test('a failed deploy cuts the description to the 140 characters GitHub '
        'accepts (presente#17: HTTP 422 Validation Failed)', () async {
      final error = 'Tests, images and backup: gate: ${'x' * 400}';
      await gh.finishDeployment(env, 42, ok: false, description: error);
      final body = calls.single.$2!;
      expect(calls.single.$1[1], 'repos/owner/demo/deployments/42/statuses');
      expect(body['state'], 'failure');
      expect((body['description'] as String).length, 140);
      expect(body['description'], startsWith('Tests, images and backup'));
      expect(body['description'], endsWith('…'));
    });

    test('a short description is sent as it is', () async {
      await gh.finishDeployment(env, 42, ok: true, description: '20261016-1');
      final body = calls.single.$2!;
      expect(body['state'], 'success');
      expect(body['description'], '20261016-1');
      expect(body['environment_url'], 'https://staging.example.com');
      expect(lines.where((l) => l.level == LogLevel.warn), isEmpty);
    });

    test('a start posts the deployment, then in_progress', () async {
      final id = await gh.startDeployment(env, 'a' * 40, 'r1');
      expect(id, 42);
      expect(calls.map((c) => c.$1[1]), [
        'repos/owner/demo/deployments',
        'repos/owner/demo/deployments/42/statuses',
      ]);
      expect(calls.last.$2!['state'], 'in_progress');
    });
  });

  test('the warning carries what gh reports', () async {
    final failing = GitHub(
      PodshipConfig.parse(_yaml),
      Log((e) => lines.add(e as LogLine)),
      runGh: (args, {input}) async =>
          throw Exception('gh api repos/owner/demo: field description'),
    );
    await failing.finishDeployment(env, 1, ok: true, description: 'r');
    expect(
      lines.single.text,
      'GitHub: deployment status failed: '
      'Exception: gh api repos/owner/demo: field description',
    );
  });

  group('the gh error', () {
    test('includes the response body GitHub sent', () {
      expect(
        ghError(
          ['api', 'repos/o/r/deployments/1/statuses', '--input', '-'],
          stdout:
              '{"message":"Validation Failed","errors":[{"resource":'
              '"DeploymentStatus","code":"custom","field":"description",'
              '"message":"description is too long (maximum is 140 '
              'characters)"}],"status":"422"}',
          stderr: 'gh: Validation Failed (HTTP 422)\n',
        ),
        'gh api repos/o/r/deployments/1/statuses --input: gh: Validation '
        'Failed (HTTP 422): description: description is too long (maximum '
        'is 140 characters)',
      );
    });

    test('without a JSON body is only stderr', () {
      expect(
        ghError(['api', 'x'], stdout: '', stderr: 'gh: Not Found (HTTP 404)'),
        'gh api x: gh: Not Found (HTTP 404)',
      );
    });
  });
}
