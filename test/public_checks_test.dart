@Tags(['unit'])
library;

import 'dart:io';

import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/plan/executor.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const _checks = '''
      public_checks:
        - {url: "https://demo.example.com/assets/config.json", content_type: application/json, contains: apiUrl}
        - {url: "https://demo.example.com/mcp", method: post, status: [200, 400, 405]}
        - {url: "http://127.0.0.1:{port:web}/missing", status: 404}
''';

String _withChecks() => sampleConfig.replaceFirst(
  '      public_url: https://demo.example.com/health\n',
  '      public_url: https://demo.example.com/health\n$_checks',
);

void main() {
  group('health.public_checks', () {
    test('parse: url, method, status list or number, content type, body', () {
      final c = PodshipConfig.parse(_withChecks(), root: '/work/demo');
      final checks = c.env('production').health.publicChecks;
      expect(checks, hasLength(3));
      expect(checks[0].contentType, 'application/json');
      expect(checks[0].contains, 'apiUrl');
      expect(checks[0].status, isEmpty);
      expect(checks[1].method, 'POST');
      expect(checks[1].status, [200, 400, 405]);
      expect(checks[2].status, [404]);
      expect(c.env('staging').health.publicChecks, isEmpty);
    });

    test('deploy: the checks run after the switch, inside the guarded steps, '
        'with ports filled in', () {
      final config = PodshipConfig.parse(_withChecks(), root: '/work/demo');
      final ctx = Ctx(
        config: config,
        ssh: Ssh(),
        log: Log.silent(),
        dryRun: true,
      );
      final s = parseState(
        'CURRENT \nENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
      );
      final r = resolveEnv(
        config,
        config.env('production'),
        s.registry,
        listening: s.listening,
      );
      final p = planDeploy(
        ctx: ctx,
        r: r,
        state: s,
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 8),
        snapshot: '/tmp/snap',
      );
      final titles = p.steps.map((x) => x.title).toList();
      final i = titles.indexOf('Public checks');
      expect(i, greaterThan(titles.indexOf('Health check')));
      expect(p.guards(i), isTrue);
      final step = p.steps[i] as PublicChecksStep;
      expect(
        step.checks.last.url,
        'http://127.0.0.1:${r.ports['web']}/missing',
      );
      // --no-public-check leaves them out.
      final q = planDeploy(
        ctx: ctx,
        r: r,
        state: s,
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 8),
        snapshot: '/tmp/snap',
        options: const DeployOptions(publicCheck: false),
      );
      expect(q.steps.map((x) => x.title), isNot(contains('Public checks')));
    });

    group('publicCheckProblem', () {
      late HttpServer server;
      late String base;
      setUp(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        base = 'http://127.0.0.1:${server.port}';
        server.listen((r) {
          switch (r.uri.path) {
            case '/config.json':
              r.response.headers.contentType = ContentType.json;
              r.response.write('{"apiUrl":"https://x/rpc/"}');
            case '/shell':
              r.response.headers.contentType = ContentType.html;
              r.response.write('<!DOCTYPE html>');
            case '/post' when r.method == 'POST':
              r.response.statusCode = 400;
            default:
              r.response.statusCode = 404;
          }
          r.response.close();
        });
      });
      tearDown(() => server.close(force: true));

      test('passes on the right status, type and body', () async {
        expect(
          await publicCheckProblem(
            PublicCheck(
              url: '$base/config.json',
              contentType: 'application/json',
              contains: 'apiUrl',
            ),
          ),
          isNull,
        );
        expect(
          await publicCheckProblem(
            PublicCheck(url: '$base/nope', status: [404]),
          ),
          isNull,
        );
        expect(
          await publicCheckProblem(
            PublicCheck(url: '$base/post', method: 'POST', status: [400, 405]),
          ),
          isNull,
        );
      });

      test('fails on an HTML shell where JSON is wanted, a missing body, '
          'a wrong status', () async {
        expect(
          await publicCheckProblem(
            PublicCheck(url: '$base/shell', contentType: 'application/json'),
          ),
          contains('content type'),
        );
        expect(
          await publicCheckProblem(
            PublicCheck(url: '$base/config.json', contains: 'mcp'),
          ),
          contains('lacks'),
        );
        expect(
          await publicCheckProblem(
            PublicCheck(url: '$base/shell', status: [404]),
          ),
          contains('status 200'),
        );
        expect(
          await publicCheckProblem(PublicCheck(url: 'http://127.0.0.1:1/x')),
          isNotNull,
        );
      });
    });
  });
}
