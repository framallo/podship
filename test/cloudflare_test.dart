import 'package:podship/src/config/config.dart';
import 'package:podship/src/integrations/changes.dart';
import 'package:podship/src/integrations/cloudflare.dart';
import 'package:podship/src/integrations/http.dart';
import 'package:podship/src/integrations/planner.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

const zoneId = '023e105f4ecef8ad9ca31a8372d0c353';
const account = 'f037e56e89293a057740de681ac9abbe';
const tunnel = '6ff42ae2-765d-4adf-8112-31c55c1551ef';
const otherTunnel = '9a1b2c3d-0000-4000-8000-0000agentes00';

String cf(String name) => 'test/api_fixtures/cloudflare/$name.json';

Fixture get(
  String path,
  String file, {
  Map<String, String>? query,
  int? times,
}) => Fixture.file('GET', path, cf(file), query: query, times: times);

/// The zone lookups for hosts under example.com.
List<Fixture> zoneFixtures() => [
  get('/client/v4/zones', 'zones_example', query: {'name': 'example.com'}),
  get('/client/v4/zones', 'zones_empty'),
];

const yaml =
    '''
project: demo
environments:
  production:
    host: prod-box
    dir: /srv/demo
    ports: {web: 8087, api: 8086}
    health: {url: "http://127.0.0.1:{port:web}/health"}
    proxy: {kind: cloudflare_tunnel, tunnel_id: $tunnel}
    dns: {provider: cloudflare}
    domains:
      - host: app.example.com
        routes:
          - {path: "^/(api|v1)/", port: api}
          - {port: web}
      - host: admin.example.com
        routes: [{port: web}]
        access: {emails: [owner@example.com], email_domains: [example.com]}
''';

EnvConfig env([String text = yaml]) =>
    PodshipConfig.parse(text).env('production');

(CloudflarePlanner, FixtureTransport) planner(List<Fixture> fixtures) {
  final t = FixtureTransport([...fixtures, ...zoneFixtures()]);
  return (
    CloudflarePlanner(
      CloudflareApi('test-token', transport: t),
      project: 'demo',
      env: env(),
    ),
    t,
  );
}

void main() {
  group('client', () {
    test('verifies the token and sends it as a bearer header', () async {
      final t = FixtureTransport([
        get('/client/v4/user/tokens/verify', 'token_verify'),
      ]);
      expect(await CloudflareApi('tok', transport: t).verifyToken(), 'active');
      expect(t.calls.single.headers['Authorization'], 'Bearer tok');
    });

    test('maps API errors with their codes', () async {
      final t = FixtureTransport([
        get('/client/v4/user/tokens/verify', 'token_invalid'),
      ]);
      expect(
        () => CloudflareApi('bad', transport: t).verifyToken(),
        throwsA(
          isA<CloudflareException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.codes, 'codes', [1000])
              .having((e) => '$e', 'text', contains('Invalid API Token')),
        ),
      );
    });

    test(
      'finds the zone by the longest suffix and takes its account',
      () async {
        final t = FixtureTransport(zoneFixtures());
        final z = await CloudflareApi(
          't',
          transport: t,
        ).zoneFor('a.b.example.com');
        expect(z.id, zoneId);
        expect(z.accountId, account);
        expect(
          [for (final c in t.calls) c.url.queryParameters['name']],
          ['a.b.example.com', 'b.example.com', 'example.com'],
        );
      },
    );

    test('reads every page of a list', () async {
      final t = FixtureTransport([
        get(
          '/client/v4/zones/z/dns_records',
          'dns_page1',
          query: {'page': '1'},
        ),
        get(
          '/client/v4/zones/z/dns_records',
          'dns_page2',
          query: {'page': '2'},
        ),
      ]);
      final r = await CloudflareApi('t', transport: t).dnsRecords('z');
      expect(r.map((x) => x.name), ['a.example.com', 'b.example.com']);
    });

    test('lists tunnels with how they are managed', () async {
      final t = FixtureTransport([
        get('/client/v4/accounts/$account/cfd_tunnel', 'tunnels'),
      ]);
      final list = await CloudflareApi('t', transport: t).tunnels(account);
      expect(list.map((x) => x.toJson()['managed']), ['remote', 'local']);
      expect(list.first.connections, 2);
      expect(list.first.cname, '$tunnel.cfargotunnel.com');
      expect(t.calls.single.url.queryParameters['is_deleted'], 'false');
    });

    test(
      'creates a remotely-managed tunnel and never exposes its token',
      () async {
        final t = FixtureTransport([
          Fixture.file(
            'POST',
            '/client/v4/accounts/$account/cfd_tunnel',
            cf('tunnel_created'),
          ),
        ]);
        final made = await CloudflareApi(
          't',
          transport: t,
        ).createTunnel(account, 'shop-mx');
        expect(t.calls.single.json, {
          'name': 'shop-mx',
          'config_src': 'cloudflare',
        });
        expect(made.toJson().toString(), isNot(contains('REDACTED')));
      },
    );

    test('the read-only client refuses writes', () async {
      final t = FixtureTransport();
      final ro = CloudflareApi('t', transport: t).readOnly();
      expect(() => ro.deleteDns('z', 'r'), throwsA(isA<ReadOnlyViolation>()));
      expect(t.calls, isEmpty);
    });
  });

  group('DNS plan', () {
    test('creates a proxied CNAME to the tunnel, marked as podship\'s', () async {
      final (p, t) = planner([
        get('/client/v4/zones/$zoneId/dns_records', 'dns_none'),
        Fixture.file(
          'POST',
          '/client/v4/zones/$zoneId/dns_records',
          cf('dns_created'),
        ),
      ]);
      final changes = await p.hostRecords(['app.example.com']);
      expect(changes.single.kind, ChangeKind.create);
      expect(t.writes, isEmpty, reason: 'planning only reads');
      final set = ChangeSet('dns', changes);
      expect(
        set.render(),
        contains(
          '+ dns_record         CNAME app.example.com\n'
          '      after:  CNAME app.example.com → $tunnel.cfargotunnel.com (proxied)',
        ),
      );
      final report = await applyChanges(set, Log.silent());
      expect(t.writes.single.json, {
        'type': 'CNAME',
        'name': 'app.example.com',
        'content': '$tunnel.cfargotunnel.com',
        'proxied': true,
        'ttl': 1,
        'comment': 'podship demo/production',
      });
      expect(report.toJson()['undo'], [
        {
          'title':
              'delete CNAME app.example.com → $tunnel.cfargotunnel.com (proxied)',
          'zone': 'example.com',
          'record_id': '0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a',
        },
      ]);
    });

    test(
      'is idempotent: nothing to do when the record already points here',
      () async {
        final (p, _) = planner([
          get('/client/v4/zones/$zoneId/dns_records', 'dns_app_this_tunnel'),
        ]);
        final set = ChangeSet('dns', await p.hostRecords(['app.example.com']));
        expect(set.isEmpty, isTrue);
        expect(set.render(), contains('= dns_record'));
      },
    );

    test(
      'repoints a record from another tunnel, with before and after',
      () async {
        final (p, t) = planner([
          get('/client/v4/zones/$zoneId/dns_records', 'dns_app_other_tunnel'),
          Fixture.file(
            'PUT',
            '/client/v4/zones/$zoneId/dns_records/372e67954025e0ba6aaa6d586b9e0b59',
            cf('dns_created'),
          ),
        ]);
        final c = (await p.hostRecords(['app.example.com'])).single;
        expect(c.kind, ChangeKind.update);
        expect(c.before!['summary'], contains(otherTunnel));
        expect(c.after!['summary'], contains(tunnel));
        expect(c.note, contains('not created by podship demo/production'));
        final report = await applyChanges(ChangeSet('dns', [c]), Log.silent());
        expect(t.writes.single.method, 'PUT');
        // The undo puts the old target back.
        await report.undos.single.run();
        expect(
          (t.writes.last.json as Map)['content'],
          '$otherTunnel.cfargotunnel.com',
        );
      },
    );

    test('deletes a conflicting A record before creating the CNAME', () async {
      final (p, _) = planner([
        get('/client/v4/zones/$zoneId/dns_records', 'dns_app_a_record'),
      ]);
      final changes = await p.hostRecords(['app.example.com']);
      expect(changes.map((c) => '${c.kind.name} ${c.key}'), [
        'delete A app.example.com',
        'create CNAME app.example.com',
      ]);
    });

    test('remove leaves a record that points elsewhere', () async {
      final (p, _) = planner([
        get('/client/v4/zones/$zoneId/dns_records', 'dns_app_other_tunnel'),
      ]);
      final c = (await p.hostRecords(['app.example.com'], remove: true)).single;
      expect(c.kind, ChangeKind.unchanged);
      expect(c.note, contains('left alone'));
    });

    test(
      'remove deletes the record that points here, and undo recreates it',
      () async {
        final (p, t) = planner([
          get('/client/v4/zones/$zoneId/dns_records', 'dns_app_this_tunnel'),
          Fixture.file(
            'DELETE',
            '/client/v4/zones/$zoneId/dns_records/372e67954025e0ba6aaa6d586b9e0b59',
            cf('dns_deleted'),
          ),
          Fixture.file(
            'POST',
            '/client/v4/zones/$zoneId/dns_records',
            cf('dns_created'),
          ),
        ]);
        final set = ChangeSet(
          'rm',
          await p.hostRecords(['app.example.com'], remove: true),
        );
        expect(set.pending.single.kind, ChangeKind.delete);
        final report = await applyChanges(set, Log.silent());
        await report.undos.single.run();
        expect(t.writes.map((c) => c.method), ['DELETE', 'POST']);
      },
    );

    test('drift: classifies where a domain points', () {
      final want = [
        CfDnsRecord(
          type: 'CNAME',
          name: 'app.example.com',
          content: '$tunnel.cfargotunnel.com',
          proxied: true,
        ),
      ];
      CfDnsRecord rec(String type, String content) => CfDnsRecord(
        type: type,
        name: 'app.example.com',
        content: content,
        proxied: true,
      );
      expect(classifyDns('app.example.com', [], want).state, 'missing');
      expect(
        classifyDns('app.example.com', [
          rec('CNAME', '$tunnel.cfargotunnel.com'),
        ], want).state,
        'ok',
      );
      final d = classifyDns('app.example.com', [
        rec('CNAME', '$otherTunnel.cfargotunnel.com'),
      ], want);
      expect(d.state, 'other_tunnel');
      expect(d.describe(), contains('DRIFT'));
      expect(
        classifyDns('app.example.com', [rec('A', '203.0.113.24')], want).state,
        'elsewhere',
      );
    });

    test('drift reads the records through the API', () async {
      final (p, t) = planner([
        get(
          '/client/v4/zones/$zoneId/dns_records',
          'dns_app_other_tunnel',
          query: {'name': 'app.example.com'},
        ),
        get(
          '/client/v4/zones/$zoneId/dns_records',
          'dns_none',
          query: {'name': 'admin.example.com'},
        ),
      ]);
      final d = await p.drift();
      expect(d.map((x) => x.state), ['other_tunnel', 'missing']);
      expect(t.writes, isEmpty);
    });
  });

  group('tunnel ingress (remotely managed)', () {
    final routes = {
      'app.example.com': [
        ResolvedRoute(null, 8087),
        ResolvedRoute('^/(api|v1)/', 8086),
      ],
    };

    test(
      'adds the host before the catch-all, paths first, keeping other rules',
      () async {
        final (p, t) = planner([
          get(
            '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
            'tunnel_config_remote',
          ),
          Fixture.file(
            'PUT',
            '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
            cf('tunnel_config_put'),
          ),
        ]);
        final c = (await p.tunnelIngress(routes)).single;
        expect(c.kind, ChangeKind.create);
        expect(
          c.after!['summary'],
          'app.example.com ^/(api|v1)/ → http://localhost:8086; app.example.com → http://localhost:8087',
        );
        await applyChanges(ChangeSet('t', [c]), Log.silent());
        final body = t.writes.single.json as Map;
        final ingress = (body['config'] as Map)['ingress'] as List;
        expect(
          ingress.map(
            (r) => '${(r as Map)['hostname']} ${r['path']} ${r['service']}',
          ),
          [
            'other.example.com null http://localhost:8082',
            'app.example.com ^/(api|v1)/ http://localhost:8086',
            'app.example.com null http://localhost:8087',
            'null null http_status:404',
          ],
        );
        expect((ingress.first as Map)['originRequest'], {'noTLSVerify': true});
        expect((body['config'] as Map)['warp-routing'], {'enabled': false});
      },
    );

    test('is idempotent once routed', () async {
      final (p, _) = planner([
        get(
          '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
          'tunnel_config_remote_routed',
        ),
      ]);
      expect(ChangeSet('t', await p.tunnelIngress(routes)).isEmpty, isTrue);
    });

    test('unroute removes the host only', () async {
      final (p, _) = planner([
        get(
          '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
          'tunnel_config_remote_routed',
        ),
      ]);
      final c = (await p.tunnelIngress({'app.example.com': const []})).single;
      expect(c.kind, ChangeKind.delete);
    });

    test('refuses a locally-managed tunnel (config.yml on the host)', () async {
      final (p, _) = planner([
        get(
          '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
          'tunnel_config_local',
        ),
      ]);
      expect(
        () => p.tunnelIngress(routes),
        throwsA(
          isA<ConfigException>().having(
            (e) => '$e',
            'msg',
            contains('managed locally'),
          ),
        ),
      );
    });

    test('withHost adds a catch-all when there is none', () {
      final c = CfTunnelConfig(ingress: []).withHost('a.com', [
        CfIngressRule(hostname: 'a.com', service: 'http://localhost:1'),
      ]);
      expect(c.ingress.map((r) => r.describe()), [
        'a.com → http://localhost:1',
        '* → http_status:404',
      ]);
    });
  });

  group('Access', () {
    test(
      'creates an app with an allow policy for the configured people',
      () async {
        final (p, t) = planner([
          get('/client/v4/accounts/$account/access/apps', 'access_apps_none'),
          Fixture.file(
            'POST',
            '/client/v4/accounts/$account/access/apps',
            cf('access_app_created'),
          ),
        ]);
        final c = (await p.access([
          'app.example.com',
          'admin.example.com',
        ])).single;
        expect(c.kind, ChangeKind.create);
        expect(c.key, 'admin.example.com');
        await applyChanges(ChangeSet('a', [c]), Log.silent());
        final body = t.writes.single.json as Map;
        expect(body['name'], 'podship demo/production admin.example.com');
        expect(body['type'], 'self_hosted');
        expect((body['policies'] as List).single, {
          'name': 'podship: allowed people',
          'decision': 'allow',
          'precedence': 1,
          'include': [
            {
              'email': {'email': 'owner@example.com'},
            },
            {
              'email_domain': {'domain': 'example.com'},
            },
          ],
        });
      },
    );

    test('teardown deletes only podship\'s app', () async {
      final (p, _) = planner([
        get('/client/v4/accounts/$account/access/apps', 'access_apps'),
      ]);
      final c = (await p.access(['admin.example.com'], remove: true)).single;
      expect(c.kind, ChangeKind.delete);
      expect(c.before!['id'], 'f174e90a-fafe-4643-bbbc-4a0ed4fc8415');
    });
  });

  group('TLS', () {
    test('Universal SSL covers one level; deeper names are flagged', () async {
      final (p, _) = planner([
        get(
          '/client/v4/zones/$zoneId/ssl/universal/settings',
          'universal_ssl_on',
        ),
      ]);
      final checks = await p.tls(['app.example.com', 'a.b.example.com']);
      expect(checks.map((c) => c.ok), [true, false]);
      expect(checks.last.detail, contains('advanced certificate'));
    });
  });
}
