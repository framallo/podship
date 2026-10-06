import 'package:podship/src/config/config.dart';
import 'package:podship/src/integrations/changes.dart';
import 'package:podship/src/integrations/cloudflare.dart';
import 'package:podship/src/integrations/http.dart';
import 'package:podship/src/integrations/planner.dart';
import 'package:podship/src/integrations/secrets.dart';
import 'package:podship/src/integrations/ses.dart';
import 'package:podship/src/integrations/sigv4.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

String ses(String name) => 'test/api_fixtures/ses/$name.json';
String cf(String name) => 'test/api_fixtures/cloudflare/$name.json';
const zoneId = '023e105f4ecef8ad9ca31a8372d0c353';

final creds = AwsCredentials(
  'AKIDEXAMPLE',
  'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
);

Fixture sesGet(String path, String file, {int? times}) =>
    Fixture.file('GET', '/v2/email$path', ses(file), times: times);

SesApi client(FixtureTransport t) => SesApi(
  creds,
  region: 'us-west-1',
  transport: t,
  clock: () => DateTime.utc(2026, 10, 6, 18),
);

EnvConfig env({
  String? mailFrom,
  String from = 'Demo <hola@app.example.com>',
}) => PodshipConfig.parse('''
project: demo
environments:
  production:
    host: prod-box
    dir: /srv/demo
    health: {url: "http://127.0.0.1:1/health"}
    proxy: {kind: cloudflare_tunnel, tunnel_id: abc}
    dns: {provider: cloudflare}
    email:
      from: "$from"
      region: us-west-1
${mailFrom == null ? '' : '      mail_from: $mailFrom'}
''').env('production');

void main() {
  group('SigV4', () {
    // AWS's published test vectors (sigv4 test suite "get-vanilla" and the
    // IAM ListUsers example of the SigV4 documentation).
    final t = DateTime.utc(2015, 8, 30, 12, 36);
    test('get-vanilla', () {
      final s = signV4(
        HttpCall('GET', Uri.parse('https://example.amazonaws.com/')),
        creds,
        region: 'us-east-1',
        service: 'service',
        now: t,
      );
      expect(
        s.parts.authorization,
        'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, '
        'SignedHeaders=host;x-amz-date, '
        'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
      );
    });
    test('IAM ListUsers example', () {
      final s = signV4(
        HttpCall(
          'GET',
          Uri.parse(
            'https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08',
          ),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          },
        ),
        creds,
        region: 'us-east-1',
        service: 'iam',
        now: t,
      );
      expect(
        s.parts.authorization,
        endsWith(
          'Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7',
        ),
      );
    });
    test('a session token is signed', () {
      final s = signV4(
        HttpCall(
          'GET',
          Uri.parse('https://email.us-west-1.amazonaws.com/v2/email/account'),
        ),
        AwsCredentials('AKID', 'secret', sessionToken: 'SESSION'),
        region: 'us-west-1',
        service: 'ses',
        now: t,
      );
      expect(s.call.headers['X-Amz-Security-Token'], 'SESSION');
      expect(s.parts.authorization, contains('x-amz-security-token'));
    });
  });

  group('SES client', () {
    test('signs every request for ses in the region', () async {
      final t = FixtureTransport([sesGet('/account', 'account_sandbox')]);
      final a = await client(t).account();
      expect(a.production, isFalse);
      expect(a.max24h, 200);
      final h = t.calls.single.headers;
      expect(
        h['Authorization'],
        startsWith(
          'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20261006/us-west-1/ses/aws4_request',
        ),
      );
      expect(h['X-Amz-Date'], '20261006T180000Z');
      expect(t.calls.single.url.host, 'email.us-west-1.amazonaws.com');
    });

    test('an unknown identity is null; other errors throw', () async {
      final t = FixtureTransport([
        sesGet('/identities/nope.example.com', 'identity_not_found'),
        Fixture.file(
          'POST',
          '/v2/email/outbound-emails',
          ses('send_rejected_sandbox'),
        ),
      ]);
      expect(await client(t).identity('nope.example.com'), isNull);
      expect(
        () => client(
          t,
        ).send(from: 'a@b.c', to: ['x@y.z'], subject: 's', text: 't'),
        throwsA(
          isA<SesException>().having((e) => e.type, 'type', 'MessageRejected'),
        ),
      );
    });

    test('an address identity is encoded in the path', () async {
      final t = FixtureTransport([
        sesGet('/identities/hola@app.example.com', 'identity_not_found'),
      ]);
      await client(t).identity('hola@app.example.com');
      expect(
        t.calls.single.url.path,
        '/v2/email/identities/hola%40app.example.com',
      );
    });

    test('creates an identity with tags and returns the DKIM tokens', () async {
      final t = FixtureTransport([
        Fixture.file('POST', '/v2/email/identities', ses('identity_created')),
      ]);
      final id = await client(
        t,
      ).createIdentity('app.example.com', tags: {'podship': 'demo/production'});
      expect(t.calls.single.json, {
        'EmailIdentity': 'app.example.com',
        'Tags': [
          {'Key': 'podship', 'Value': 'demo/production'},
        ],
      });
      expect(id.dkimTokens, hasLength(3));
      expect(
        dkimRecords('app.example.com', id.dkimTokens).first.$3,
        'CNAME k1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa._domainkey.app.example.com → k1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.dkim.amazonses.com',
      );
    });

    test('sends a plain-text email', () async {
      final t = FixtureTransport([
        Fixture.file('POST', '/v2/email/outbound-emails', ses('sent')),
      ]);
      final id = await client(t).send(
        from: 'Demo <hola@app.example.com>',
        to: ['success@simulator.amazonses.com'],
        subject: 'podship test',
        text: 'hello',
      );
      expect(id, startsWith('0100019abcde'));
      final body = t.calls.single.json as Map;
      expect(body['FromEmailAddress'], 'Demo <hola@app.example.com>');
      expect((body['Destination'] as Map)['ToAddresses'], [
        'success@simulator.amazonses.com',
      ]);
    });
  });

  group('can it send?', () {
    test('a verified parent domain lets a subdomain send', () async {
      final t = FixtureTransport([
        sesGet('/account', 'account_production'),
        sesGet('/identities/hola@app.example.com', 'identity_not_found'),
        sesGet('/identities/app.example.com', 'identity_not_found'),
        sesGet('/identities/example.com', 'identity_verified_parent'),
      ]);
      final c = await checkSender(client(t), 'Demo <hola@app.example.com>');
      expect(c.canSend, isTrue);
      expect(c.sendingIdentity, 'example.com');
      expect(c.problems, isEmpty);
      expect(t.writes, isEmpty);
    });

    test('the sandbox is reported', () async {
      final t = FixtureTransport([
        sesGet('/account', 'account_sandbox'),
        sesGet('/identities/hola@app.example.com', 'identity_not_found'),
        sesGet('/identities/app.example.com', 'identity_pending'),
        sesGet('/identities/example.com', 'identity_not_found'),
      ]);
      final c = await checkSender(client(t), 'hola@app.example.com');
      expect(c.canSend, isFalse);
      expect(c.problems.join('\n'), contains('sandbox'));
      expect(c.domainIdentity!.verificationStatus, 'PENDING');
      expect((c.toJson()['account'] as Map)['sandbox'], isTrue);
    });
  });

  group('email plan', () {
    List<Fixture> zones() => [
      Fixture.file(
        'GET',
        '/client/v4/zones',
        cf('zones_example'),
        query: {'name': 'example.com'},
      ),
      Fixture.file('GET', '/client/v4/zones', cf('zones_empty')),
    ];

    EmailPlanner planner(FixtureTransport t, EnvConfig e) => EmailPlanner(
      client(t),
      email: e.email!,
      project: 'demo',
      env: 'production',
      dns: CloudflarePlanner(
        CloudflareApi('tok', transport: t),
        project: 'demo',
        env: e,
      ),
    );

    test(
      'nothing can send: create the identity, then its DKIM records, then MAIL FROM',
      () async {
        final t = FixtureTransport([
          sesGet('/account', 'account_production'),
          sesGet('/identities/*', 'identity_not_found', times: 4),
          ...zones(),
          Fixture.file(
            'GET',
            '/client/v4/zones/$zoneId/dns_records',
            cf('dns_none'),
          ),
          Fixture.file('POST', '/v2/email/identities', ses('identity_created')),
          Fixture.file(
            'POST',
            '/client/v4/zones/$zoneId/dns_records',
            cf('dns_created'),
          ),
          Fixture.file(
            'PUT',
            '/v2/email/identities/app.example.com/mail-from',
            ses('empty_ok'),
          ),
        ]);
        final e = env(mailFrom: 'bounce.app.example.com');
        final set = await planner(t, e).plan();
        expect(t.writes, isEmpty, reason: 'planning only reads');
        expect(
          set.pending.map((c) => '${c.kind.name} ${c.resource} ${c.key}'),
          [
            'create ses_identity app.example.com',
            'create dns_record DKIM CNAMEs of app.example.com',
            'create ses_mail_from app.example.com',
            'create dns_record MX bounce.app.example.com',
            'create dns_record TXT bounce.app.example.com',
          ],
        );
        final text = set.render();
        expect(text, contains('tokens come from SES'));
        expect(
          text,
          contains(
            'MX bounce.app.example.com → 10 feedback-smtp.us-west-1.amazonses.com',
          ),
        );

        final report = await applyChanges(set, Log.silent());
        final writes = [for (final w in t.writes) '${w.method} ${w.url.path}'];
        expect(writes.first, 'POST /v2/email/identities');
        final dkim = [
          for (final w in t.writes)
            if (w.url.host == 'api.cloudflare.com' &&
                (w.json as Map)['name'].toString().contains('_domainkey'))
              w.json as Map,
        ];
        expect(dkim.map((r) => r['content']), [
          'k1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.dkim.amazonses.com',
          'k2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.dkim.amazonses.com',
          'k3cccccccccccccccccccccccccccccc.dkim.amazonses.com',
        ]);
        expect(
          dkim.every((r) => r['proxied'] == false),
          isTrue,
          reason: 'DKIM must not be proxied',
        );
        final mf = t.writes
            .firstWhere((w) => w.url.path.endsWith('/mail-from'))
            .json;
        expect(mf, {
          'MailFromDomain': 'bounce.app.example.com',
          'BehaviorOnMxFailure': 'USE_DEFAULT_VALUE',
        });
        expect(
          report.undos.first.title,
          'delete the SES identity app.example.com',
        );
      },
    );

    test('a verified parent: nothing to change', () async {
      final t = FixtureTransport([
        sesGet('/account', 'account_production'),
        sesGet('/identities/hola@app.example.com', 'identity_not_found'),
        sesGet('/identities/app.example.com', 'identity_not_found'),
        sesGet('/identities/example.com', 'identity_verified_parent'),
      ]);
      final set = await planner(t, env()).plan();
      expect(set.isEmpty, isTrue);
      expect(set.checks.map((c) => c.ok), everyElement(isTrue));
    });

    test('a pending identity: publish its DKIM records only', () async {
      final t = FixtureTransport([
        sesGet('/account', 'account_sandbox'),
        sesGet('/identities/hola@app.example.com', 'identity_not_found'),
        sesGet('/identities/app.example.com', 'identity_pending'),
        sesGet('/identities/example.com', 'identity_not_found'),
        ...zones(),
        Fixture.file(
          'GET',
          '/client/v4/zones/$zoneId/dns_records',
          cf('dns_none'),
        ),
      ]);
      final set = await planner(t, env()).plan();
      expect(set.pending.map((c) => c.key), [
        'CNAME t1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa._domainkey.app.example.com',
        'CNAME t2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb._domainkey.app.example.com',
        'CNAME t3cccccccccccccccccccccccccccccc._domainkey.app.example.com',
      ]);
      expect(
        set.checks.where((c) => !c.ok).map((c) => c.name),
        contains('SES account (us-west-1)'),
      );
    });

    test(
      'without Cloudflare, the plan lists the records to add by hand',
      () async {
        final t = FixtureTransport([
          sesGet('/account', 'account_production'),
          sesGet('/identities/hola@app.example.com', 'identity_not_found'),
          sesGet('/identities/app.example.com', 'identity_pending'),
          sesGet('/identities/example.com', 'identity_not_found'),
        ]);
        final set = await EmailPlanner(
          client(t),
          email: env().email!,
          project: 'demo',
          env: 'production',
        ).plan();
        expect(set.isEmpty, isTrue);
        expect(
          set.checks.first.detail + set.checks.map((c) => c.detail).join(),
          contains(
            't1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa._domainkey.app.example.com',
          ),
        );
      },
    );

    test(
      'teardown leaves an identity that this environment did not create',
      () async {
        final t = FixtureTransport([
          sesGet('/identities/example.com', 'identity_verified_parent'),
        ]);
        final e = PodshipConfig.parse('''
project: demo
environments:
  production:
    host: h
    dir: /srv/d
    health: {url: "http://127.0.0.1:1/"}
    email: {from: "a@example.com", region: us-west-1}
''').env('production');
        final set = await EmailPlanner(
          client(t),
          email: e.email!,
          project: 'demo',
          env: 'production',
        ).teardown();
        expect(set.isEmpty, isTrue);
        expect(set.changes.single.note, contains('left alone'));
      },
    );

    test('teardown deletes a tagged identity', () async {
      final t = FixtureTransport([
        sesGet('/identities/app.example.com', 'identity_pending'),
      ]);
      final set = await EmailPlanner(
        client(t),
        email: env().email!,
        project: 'demo',
        env: 'production',
      ).teardown();
      expect(set.pending.single.kind, ChangeKind.delete);
    });
  });

  group('config', () {
    test('email env goes to the server container without credentials', () {
      final e = env();
      expect(e.email!.environment, {
        'EMAIL_FROM': 'Demo <hola@app.example.com>',
        'SES_REGION': 'us-west-1',
        'EMAIL_PROVIDER': 'ses',
      });
      expect(e.email!.domain, 'app.example.com');
    });

    test('rejects a from without an address', () {
      expect(() => env(from: 'Demo'), throwsA(isA<ConfigException>()));
    });

    test('a tunnel without a config file is remotely managed', () {
      expect(env().proxy.remoteManaged, isTrue);
    });
  });
}
