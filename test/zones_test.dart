// Zone resolution, drift and post-apply checks against fixtures that
// mirror the owner's account on 2026-10-06 (tunnel ids shortened to a
// placeholder): cazafacturas.mx apex is a Tunnel CNAME to the laptop
// tunnel 24fb406b…, www is a CNAME to the apex; densitylabs.io has boceto,
// boceto-mockups, bocetos (a Single Redirect to boceto) and
// presente-staging on the same tunnel.
@Tags(['unit'])
library;

import 'package:podship/src/api/tunnel.dart';
import 'package:podship/src/config/config.dart';
import 'package:podship/src/integrations/cloudflare.dart';
import 'package:podship/src/integrations/doh.dart';
import 'package:podship/src/integrations/http.dart';
import 'package:podship/src/integrations/planner.dart';
import 'package:test/test.dart';

String cf(String name) => 'test/api_fixtures/cloudflare/$name.json';
const laptop = '24fb406b-0000-4000-8000-0000laptop000';
const vps = '6ff42ae2-765d-4adf-8112-31c55c1551ef';
const cazaZone = 'cz0000000000000000000000000000mx';
const dlZone = 'dl0000000000000000000000000000io';

Fixture get(String path, String file, {Map<String, String>? query}) =>
    Fixture.file('GET', '/client/v4$path', cf(file), query: query);

/// A token that can read only densitylabs.io.
FixtureTransport densitylabsOnly() => FixtureTransport([
  get('/zones', 'zones_densitylabs', query: {'name': 'densitylabs.io'}),
  get('/zones', 'zones_empty'),
]);

/// A token that can read both zones.
List<Fixture> bothZones() => [
  get('/zones', 'zones_densitylabs', query: {'name': 'densitylabs.io'}),
  get('/zones', 'zones_cazafacturas', query: {'name': 'cazafacturas.mx'}),
  get('/zones', 'zones_empty'),
];

EnvConfig caza(String tunnel, {String? zone}) => PodshipConfig.parse('''
project: cazafacturas
environments:
  production:
    host: caza-vps
    dir: /srv/cazafacturas
    health: {url: "http://127.0.0.1:1/health"}
    proxy: {kind: cloudflare_tunnel, tunnel_id: $tunnel}
    dns: {provider: cloudflare${zone == null ? '' : ', zone: $zone'}}
    domains:
      - {host: cazafacturas.mx, routes: [{port: "8087"}]}
      - {host: www.cazafacturas.mx, routes: [{port: "8087"}]}
''').env('production');

void main() {
  group('zone of a hostname', () {
    test('refuses a hostname whose zone the token cannot read', () async {
      // The cloudflared bug: an origin cert for densitylabs.io and the name
      // www.cazafacturas.mx made www.cazafacturas.mx.densitylabs.io.
      final t = densitylabsOnly();
      await expectLater(
        CloudflareApi('t', transport: t).zoneFor('www.cazafacturas.mx'),
        throwsA(
          isA<CloudflareException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('no zone for www.cazafacturas.mx'),
              contains('cazafacturas.mx'),
            ),
          ),
        ),
      );
      expect(t.writes, isEmpty);
    });

    test(
      'refuses dns.zone that does not hold the hostname, before any call',
      () async {
        final t = FixtureTransport();
        await expectLater(
          CloudflareApi(
            't',
            transport: t,
          ).zoneFor('www.cazafacturas.mx', zoneName: 'densitylabs.io'),
          throwsA(
            isA<CloudflareException>().having(
              (e) => e.message,
              'm',
              contains('not in the zone densitylabs.io'),
            ),
          ),
        );
        expect(t.calls, isEmpty);
      },
    );

    test('ignores a zone the API returns under another name', () async {
      // Even if a name filter matched loosely, only an exact zone name counts.
      final t = FixtureTransport([get('/zones', 'zones_densitylabs')]);
      await expectLater(
        CloudflareApi('t', transport: t).zoneFor('www.cazafacturas.mx'),
        throwsA(isA<CloudflareException>()),
      );
    });

    test('takes the longest matching zone', () async {
      final t = FixtureTransport(bothZones());
      final z = await CloudflareApi(
        't',
        transport: t,
      ).zoneFor('presente-staging.densitylabs.io');
      expect(z.name, 'densitylabs.io');
      final z2 = await CloudflareApi(
        't',
        transport: t,
      ).zoneFor('cazafacturas.mx');
      expect(z2.id, cazaZone);
    });

    test('a DNS plan for a zone outside the token creates nothing', () async {
      final t = densitylabsOnly();
      final p = CloudflarePlanner(
        CloudflareApi('t', transport: t),
        project: 'cazafacturas',
        env: caza(vps),
      );
      await expectLater(
        p.hostRecords(['www.cazafacturas.mx']),
        throwsA(isA<CloudflareException>()),
      );
      expect(t.writes, isEmpty);
    });
  });

  group('cloudflared route dns (locally-managed tunnels)', () {
    test('picks the origin cert of the longest matching zone only', () {
      final certs = {
        'densitylabs.io': '/c/dl.pem',
        'staging.densitylabs.io': '/c/st.pem',
      };
      expect(originCertFor(certs, 'www.cazafacturas.mx'), isNull);
      expect(originCertFor(certs, 'boceto.densitylabs.io'), '/c/dl.pem');
      expect(originCertFor(certs, 'a.staging.densitylabs.io'), '/c/st.pem');
      expect(originCertFor(certs, 'xdensitylabs.io'), isNull);
    });

    test('reads the name cloudflared actually created', () {
      expect(
        routeDnsName(
          '2026-10-06T17:00:00Z INF Added CNAME www.cazafacturas.mx.densitylabs.io which will route to this tunnel tunnelID=$laptop',
        ),
        'www.cazafacturas.mx.densitylabs.io',
      );
      expect(
        routeDnsName(
          'INF boceto.densitylabs.io is already configured to route to your tunnel tunnelID=$laptop',
        ),
        'boceto.densitylabs.io',
      );
    });
  });

  group('drift on the current account', () {
    List<Fixture> records() => [
      get(
        '/zones/$cazaZone/dns_records',
        'dns_caza_apex',
        query: {'name': 'cazafacturas.mx'},
      ),
      get(
        '/zones/$cazaZone/dns_records',
        'dns_caza_www',
        query: {'name': 'www.cazafacturas.mx'},
      ),
    ];

    test('the laptop tunnel: apex and www (through the apex) are ok', () async {
      final t = FixtureTransport([...bothZones(), ...records()]);
      final d = await CloudflarePlanner(
        CloudflareApi('t', transport: t),
        project: 'cazafacturas',
        env: caza(laptop),
      ).drift();
      expect(d.map((x) => x.state), ['ok', 'ok']);
      expect(
        d.last.actual,
        startsWith('www.cazafacturas.mx → cazafacturas.mx: '),
      );
    });

    test(
      'an environment on the VPS tunnel sees both pointing to another tunnel',
      () async {
        final t = FixtureTransport([...bothZones(), ...records()]);
        final d = await CloudflarePlanner(
          CloudflareApi('t', transport: t),
          project: 'cazafacturas',
          env: caza(vps),
        ).drift();
        expect(d.map((x) => x.state), ['other_tunnel', 'other_tunnel']);
        expect(d.first.describe(), contains(laptop));
        expect(t.writes, isEmpty);
      },
    );

    test('lists the densitylabs.io records on the laptop tunnel', () async {
      final t = FixtureTransport([
        ...bothZones(),
        get('/zones/$dlZone/dns_records', 'dns_densitylabs_all'),
      ]);
      final api = CloudflareApi('t', transport: t);
      final z = await api.zoneFor('densitylabs.io');
      final recs = await api.dnsRecords(z.id);
      expect(recs.map((r) => r.name), [
        'boceto.densitylabs.io',
        'boceto-mockups.densitylabs.io',
        'bocetos.densitylabs.io',
        'presente-staging.densitylabs.io',
      ]);
      expect(
        recs.every((r) => r.content == '$laptop.cfargotunnel.com' && r.proxied),
        isTrue,
      );
    });
  });

  group('post-apply checks', () {
    test('DoH follows the CNAME to the edge addresses', () async {
      final t = FixtureTransport([
        Fixture.file(
          'GET',
          '/dns-query',
          cf('doh_a_proxied'),
          query: {'name': 'www.cazafacturas.mx', 'type': 'A'},
        ),
      ]);
      final a = await DohResolver(
        transport: t,
      ).addresses('www.cazafacturas.mx');
      expect(a, ['104.21.48.1', '172.67.150.2']);
      expect(t.calls.single.headers['Accept'], 'application/dns-json');
      expect(t.calls.single.url.host, 'cloudflare-dns.com');
    });

    test(
      'NXDOMAIN is no address (and DoH has no local negative cache)',
      () async {
        final t = FixtureTransport([
          Fixture.file('GET', '/dns-query', cf('doh_nxdomain')),
        ]);
        expect(
          await DohResolver(transport: t).addresses('new.cazafacturas.mx'),
          isEmpty,
        );
      },
    );

    test('the public check pins the edge address with --resolve', () {
      expect(
        pinnedCurlArgs('https://www.cazafacturas.mx/health', '104.21.48.1'),
        [
          '-fsS',
          '-o',
          '/dev/null',
          '--max-time',
          '10',
          '--resolve',
          'www.cazafacturas.mx:443:104.21.48.1',
          'https://www.cazafacturas.mx/health',
        ],
      );
    });
  });
}
