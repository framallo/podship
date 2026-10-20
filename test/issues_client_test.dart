// REV-18 (podship#1): a failed suite after the deploy opens an issue in the
// project's tracker (Boceto) over its HTTP API.
@Tags(['unit'])
library;

import 'package:podship/podship.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('issues: in podship.yaml', () {
    test('a Boceto tracker: url, project and the token variable', () {
      final c = PodshipConfig.parse(
        '$sampleConfig\n'
        'issues:\n'
        '  tracker: boceto\n'
        '  url: https://boceto.example.com\n'
        '  project: demo\n',
      );
      final i = c.issues!;
      expect(i.tracker, 'boceto');
      expect(i.url, 'https://boceto.example.com');
      expect(i.project, 'demo');
      expect(PodshipConfig.parse(sampleConfig).issues, isNull);
    });

    test('only boceto is known', () {
      expect(
        () => PodshipConfig.parse(
          '$sampleConfig\nissues: {tracker: jira, url: x, project: y}\n',
        ),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('BocetoIssues', () {
    test('create posts the create_issue tool with the bearer token', () async {
      final http = FixtureTransport([
        Fixture(
          'POST',
          '/api/v1/tools/create_issue',
          HttpReply(
            200,
            '{"number": 7, "url": "https://boceto.example.com/w/x/p/demo/issues/7"}',
          ),
        ),
      ]);
      final issues = BocetoIssues(
        url: 'https://boceto.example.com/',
        project: 'demo',
        token: 'bct_secret',
        transport: http,
      );
      final made = await issues.create(
        title: 'Tests after deploy: ui failed on production',
        body: 'release 20261019-120000-a0dc2b0\n2 failed',
      );
      expect(made.number, 7);
      expect(made.url, endsWith('/issues/7'));
      final call = http.writes.single;
      expect(
        call.url.toString(),
        'https://boceto.example.com/api/v1/tools/create_issue',
      );
      expect(call.headers['Authorization'], 'Bearer bct_secret');
      expect(call.headers['Content-Type'], startsWith('application/json'));
      final json = call.json as Map;
      expect(json['project'], 'demo');
      expect(json['title'], 'Tests after deploy: ui failed on production');
      expect(json['description'], contains('2 failed'));
      expect(json['labels'], ['needs-triage']);
    });

    test('an error reply throws with the status and message', () async {
      final http = FixtureTransport([
        Fixture(
          'POST',
          '/api/v1/tools/create_issue',
          HttpReply(401, '{"error":"unauthorized","message":"bad token"}'),
        ),
      ]);
      final issues = BocetoIssues(
        url: 'https://boceto.example.com',
        project: 'demo',
        token: 'bct_x',
        transport: http,
      );
      await expectLater(
        issues.create(title: 't', body: 'b'),
        throwsA(
          isA<IssuesException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('401'), contains('bad token')),
          ),
        ),
      );
    });
  });

  group('Integrations.issues', () {
    final cfg = IssuesConfig(
      tracker: 'boceto',
      url: 'https://boceto.example.com',
      project: 'demo',
    );
    test('the token comes from the secret store; none, no client', () {
      final http = FixtureTransport();
      final with_ = Integrations(
        secrets: MapSecrets({bocetoTokenKey: 'bct_1'}),
        transport: http,
      );
      final client = with_.issues(cfg)!;
      expect(client.token, 'bct_1');
      expect(client.url, 'https://boceto.example.com');
      expect(identical(client.transport, http), isTrue);
      final without = Integrations(secrets: MapSecrets({}), transport: http);
      expect(without.issues(cfg), isNull);
    });

    test('BOCETO_TOKEN in the environment stands in for the store', () {
      final s = SystemSecrets(environment: {'BOCETO_TOKEN': 'bct_env'});
      expect(s.read(bocetoTokenKey), 'bct_env');
    });
  });
}
