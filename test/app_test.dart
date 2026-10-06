// app setup / teardown, domain add with Cloudflare, and the protocol's
// approval rules, through the library with a fake ssh and recorded API
// fixtures. Nothing here reaches a server, Cloudflare or AWS.

import 'dart:convert';

import 'package:podship/podship.dart';
import 'package:podship/src/cli/runner.dart';
import 'package:podship/src/ops/app_ops.dart';
import 'package:podship/src/ops/context.dart';
import 'package:test/test.dart';

String cf(String name) => 'test/api_fixtures/cloudflare/$name.json';
String ses(String name) => 'test/api_fixtures/ses/$name.json';
const zoneId = '023e105f4ecef8ad9ca31a8372d0c353';
const account = 'f037e56e89293a057740de681ac9abbe';
const tunnel = '6ff42ae2-765d-4adf-8112-31c55c1551ef';

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
    email: {from: "Demo <hola@app.example.com>", region: us-west-1}
    domains:
      - host: app.example.com
        routes:
          - {path: "^/(api|v1)/", port: api}
          - {port: web}
      - host: admin.example.com
        routes: [{port: web}]
        access: {emails: [owner@example.com]}
''';

/// Answers the scripts podship sends: the lock, the state (with
/// [registry]), and everything else with success. Records every script.
class FakeSsh extends Ssh {
  FakeSsh({this.registry = ''});
  String registry;
  final scripts = <String>[];

  String _answer(String script) {
    scripts.add(script);
    if (script.contains('owner.json') && script.contains('LOCKED')) {
      return 'LOCKED\n';
    }
    if (script.contains('REGISTRY-BEGIN')) {
      return 'REGISTRY-BEGIN\n$registry\nREGISTRY-END\nPORTS \n';
    }
    return '';
  }

  @override
  Future<String> capture(
    String host,
    String script, {
    List<int>? stdin,
  }) async => _answer(script);

  @override
  Future<({int exitCode, String stdout, String stderr})> captureResult(
    String host,
    String script, {
    List<int>? stdin,
  }) async => (exitCode: 0, stdout: _answer(script), stderr: '');

  @override
  Future<int> lines(
    String host,
    String script,
    void Function(String line, bool stderr) onLine,
  ) async {
    _answer(script);
    return 0;
  }
}

Fixture g(String path, String file, {Map<String, String>? query, int? times}) =>
    Fixture.file('GET', path, file, query: query, times: times);

/// The account before setup: no records, an empty remote tunnel, no Access
/// apps, no SES identity.
List<Fixture> before() => [
  g('/client/v4/zones', cf('zones_example'), query: {'name': 'example.com'}),
  g('/client/v4/zones', cf('zones_empty')),
  g('/client/v4/zones/$zoneId/dns_records', cf('dns_none')),
  g(
    '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
    cf('tunnel_config_remote'),
  ),
  g('/client/v4/accounts/$account/access/apps', cf('access_apps_none')),
  g('/client/v4/zones/$zoneId/ssl/universal/settings', cf('universal_ssl_on')),
  g('/v2/email/account', ses('account_production')),
  g('/v2/email/identities/*', ses('identity_not_found')),
];

/// The write fixtures of a successful setup.
List<Fixture> writes() => [
  Fixture.file(
    'POST',
    '/client/v4/zones/$zoneId/dns_records',
    cf('dns_created'),
  ),
  Fixture.file(
    'PUT',
    '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
    cf('tunnel_config_put'),
  ),
  Fixture.file(
    'POST',
    '/client/v4/accounts/$account/access/apps',
    cf('access_app_created'),
  ),
  Fixture.file('POST', '/v2/email/identities', ses('identity_created')),
  Fixture.file(
    'DELETE',
    '/client/v4/zones/$zoneId/dns_records/*',
    cf('dns_deleted'),
  ),
  Fixture.file('DELETE', '/v2/email/identities/*', ses('empty_ok')),
  Fixture.file('GET', '/dns-query', cf('doh_a_proxied')),
];

({Podship api, FixtureTransport http, FakeSsh ssh}) setup(
  List<Fixture> fixtures, {
  bool dryRun = false,
  String registry = '',
}) {
  final http = FixtureTransport(fixtures);
  final ssh = FakeSsh(registry: registry);
  final api = Podship(
    PodshipConfig.parse(yaml),
    dryRun: dryRun,
    actor: 'test@example.com',
    ssh: ssh,
    integrations: Integrations(
      secrets: MapSecrets({
        cloudflareTokenKey: 'cf-test-token',
        awsCredentialsKey: AwsCredentials('AKIDEXAMPLE', 'secret').toJson(),
      }),
      transport: http,
    ),
  );
  return (api: api, http: http, ssh: ssh);
}

/// Runs an operation: its events must be read for it to finish.
Future<OperationResult> finish(Operation op) async {
  await op.events.drain<void>();
  return op.result;
}

void main() {
  group('app setup', () {
    test(
      'one plan: registry, tunnel route, DNS, Access, TLS, SES, DKIM — read-only',
      () async {
        final t = setup(before());
        final set = await t.api.appPlan('production');
        expect(t.http.writes, isEmpty);
        expect(set.pending.map((c) => '${c.symbol} ${c.resource} ${c.key}'), [
          '+ registry demo/production',
          '+ tunnel_ingress tunnel $tunnel: app.example.com',
          '+ tunnel_ingress tunnel $tunnel: admin.example.com',
          '+ dns_record CNAME app.example.com',
          '+ dns_record CNAME admin.example.com',
          '+ access_app admin.example.com',
          '+ ses_identity app.example.com',
          '+ dns_record DKIM CNAMEs of app.example.com',
        ]);
        expect(
          set.checks.map((c) => c.name),
          containsAll(['TLS app.example.com', 'SES account (us-west-1)']),
        );
        expect(set.render(), contains('(plan ${set.id})'));
      },
    );

    test('--plan (dry run) emits the plan and changes nothing', () async {
      final t = setup(before(), dryRun: true);
      final op = t.api.appSetup('production');
      final events = await op.events.toList();
      final r = await op.result;
      expect(r.ok, isTrue);
      expect(
        events.whereType<PlanReady>().single.text,
        contains('+ dns_record'),
      );
      expect(t.http.writes, isEmpty);
      expect(
        t.ssh.scripts.where((s) => s.contains('LOCKED')),
        isEmpty,
        reason: 'no lock on a dry run',
      );
    });

    test('refuses to apply when the plan is not the approved one', () async {
      final t = setup([...before(), ...writes()]);
      final r = await finish(
        t.api.appSetup('production', planId: 'aaaaaaaaaaaa'),
      );
      expect(r.ok, isFalse);
      expect(r.error, contains('the plan changed since it was approved'));
      expect(t.http.writes, isEmpty);
    });

    test(
      'applies the approved plan, records the undo in history, checks DNS over DoH',
      () async {
        final t = setup([...before(), ...writes()]);
        final id = (await t.api.appPlan('production')).id;
        t.http.calls.clear();
        final r = await finish(t.api.appSetup('production', planId: id));
        expect(r.ok, isTrue, reason: r.error);
        final w = [for (final c in t.http.writes) '${c.method} ${c.url.path}'];
        expect(w, [
          'PUT /client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
          'PUT /client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
          'POST /client/v4/zones/$zoneId/dns_records',
          'POST /client/v4/zones/$zoneId/dns_records',
          'POST /client/v4/accounts/$account/access/apps',
          'POST /v2/email/identities',
          'POST /client/v4/zones/$zoneId/dns_records',
          'POST /client/v4/zones/$zoneId/dns_records',
          'POST /client/v4/zones/$zoneId/dns_records',
        ]);
        final applied = r.data['applied'] as Map;
        expect(applied['plan_id'], id);
        expect(
          (applied['undo'] as List).first,
          containsPair('title', startsWith('delete the DKIM CNAMEs')),
        );
        expect((r.data['checks'] as List).first, containsPair('ok', true));
        expect(
          t.http.calls.any((c) => c.url.host == 'cloudflare-dns.com'),
          isTrue,
        );
        // The history record went to the server, without the token.
        final history = t.ssh.scripts
            .where((s) => s.contains('/history/demo/production'))
            .join();
        expect(history, isNotEmpty);
        expect(jsonEncode(r.toJson()), isNot(contains('cf-test-token')));
        expect(jsonEncode(r.toJson()), isNot(contains('AKIDEXAMPLE')));
        // The registry was written.
        expect(t.ssh.scripts.any((s) => s.contains('registry.yaml')), isTrue);
      },
    );

    test('a failed change undoes the ones before it (rollback)', () async {
      final t = setup([
        ...before(),
        Fixture.file(
          'POST',
          '/client/v4/accounts/$account/access/apps',
          cf('error_auth'),
        ),
        ...writes(),
      ]);
      final id = (await t.api.appPlan('production')).id;
      t.http.calls.clear();
      final r = await finish(t.api.appSetup('production', planId: id));
      expect(r.ok, isFalse);
      expect(r.error, contains('Authentication error'));
      final failed = r.data['failed'] as Map;
      expect(failed['undone'], [
        'delete CNAME admin.example.com → $tunnel.cfargotunnel.com (proxied)',
        'delete CNAME app.example.com → $tunnel.cfargotunnel.com (proxied)',
        'restore the tunnel rules of admin.example.com',
        'restore the tunnel rules of app.example.com',
        'remove demo/production from the registry',
      ]);
      expect(t.http.writes.where((c) => c.method == 'DELETE'), hasLength(2));
      expect(
        t.http.writes.any((c) => c.url.path == '/v2/email/identities'),
        isFalse,
        reason: 'stops at the failure',
      );
    });

    test('idempotent: after setup, the plan is empty', () async {
      // Registry entry as setup wrote it.
      final probe = setup(before());
      final p = EnvPlanning(
        Ctx(config: probe.api.config, ssh: probe.ssh, log: Log.silent()),
        probe.api.config.env('production'),
        probe.api.integrations,
      );
      final entry = (await p.resolved()).entry;
      final registry = (Registry.parse('')..put(entry)).render();
      final t = setup([
        g(
          '/client/v4/zones',
          cf('zones_example'),
          query: {'name': 'example.com'},
        ),
        g('/client/v4/zones', cf('zones_empty')),
        g(
          '/client/v4/zones/$zoneId/dns_records',
          cf('dns_app_this_tunnel'),
          query: {'name': 'app.example.com'},
        ),
        g(
          '/client/v4/zones/$zoneId/dns_records',
          cf('dns_admin_this_tunnel'),
          query: {'name': 'admin.example.com'},
        ),
        g(
          '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
          cf('tunnel_config_remote_all'),
        ),
        g('/client/v4/accounts/$account/access/apps', cf('access_apps')),
        g(
          '/client/v4/zones/$zoneId/ssl/universal/settings',
          cf('universal_ssl_on'),
        ),
        g('/v2/email/account', ses('account_production')),
        g(
          '/v2/email/identities/hola@app.example.com',
          ses('identity_not_found'),
        ),
        g('/v2/email/identities/app.example.com', ses('identity_not_found')),
        g('/v2/email/identities/example.com', ses('identity_verified_parent')),
      ], registry: registry);
      final set = await t.api.appPlan('production');
      expect(set.isEmpty, isTrue, reason: set.render());
      expect(
        set.changes.map((c) => c.resource).toSet(),
        containsAll(['registry', 'tunnel_ingress', 'dns_record', 'access_app']),
      );
      expect(set.checks.where((c) => !c.ok), isEmpty);
    });

    test(
      'teardown: removes DNS that points here, routes and podship\'s Access app; SES stays',
      () async {
        final t = setup([
          g(
            '/client/v4/zones',
            cf('zones_example'),
            query: {'name': 'example.com'},
          ),
          g('/client/v4/zones', cf('zones_empty')),
          g(
            '/client/v4/zones/$zoneId/dns_records',
            cf('dns_app_this_tunnel'),
            query: {'name': 'app.example.com'},
          ),
          g(
            '/client/v4/zones/$zoneId/dns_records',
            cf('dns_none'),
            query: {'name': 'admin.example.com'},
          ),
          g(
            '/client/v4/accounts/$account/cfd_tunnel/$tunnel/configurations',
            cf('tunnel_config_remote_routed'),
          ),
          g('/client/v4/accounts/$account/access/apps', cf('access_apps')),
        ]);
        final set = await t.api.teardownPlan('production');
        expect(set.pending.map((c) => '${c.symbol} ${c.resource} ${c.key}'), [
          '- access_app admin.example.com',
          '- dns_record CNAME app.example.com',
          '- tunnel_ingress tunnel $tunnel: app.example.com',
        ]);
        expect(set.changes.any((c) => c.resource == 'ses_identity'), isFalse);
        expect(t.http.writes, isEmpty);
      },
    );
  });

  group('domain add --provider cloudflare', () {
    test('plans the route, the record and Access for one host', () async {
      final t = setup(before());
      final set = await t.api.domainPlan(
        'production',
        hosts: ['admin.example.com'],
        provider: 'cloudflare',
      );
      expect(set.pending.map((c) => c.resource), [
        'tunnel_ingress',
        'dns_record',
        'access_app',
      ]);
    });

    test('an unknown host is refused before any call', () async {
      final t = setup(before());
      expect(
        () => t.api.domainPlan('production', hosts: ['x.example.com']),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('protocol', () {
    OperationRequest req(
      String op, {
      Map<String, Object?> params = const {},
      String? origin,
      bool dryRun = false,
    }) => OperationRequest(
      operation: op,
      project: 'demo',
      env: 'production',
      params: params,
      origin: origin,
      dryRun: dryRun,
    );

    Future<Map<String, Object?>> last(Podship api, OperationRequest r) async =>
        (await dispatch(api, r).toList()).last;

    test('MCP may only plan: applying is refused, planning works', () async {
      final t = setup(before());
      final refused = await last(
        t.api,
        req('app.setup', params: {'plan_id': 'x'}, origin: 'mcp'),
      );
      expect(refused['ok'], isFalse);
      expect(refused['error'], contains('MCP clients may only plan'));
      final plan = await last(t.api, req('app.plan', origin: 'mcp'));
      expect(plan['ok'], isTrue);
      expect(((plan['data'] as Map)['value'] as Map)['plan_id'], hasLength(12));
      final dry = await last(
        t.api,
        req('dns.apply', origin: 'mcp', dryRun: true),
      );
      expect(dry['ok'], isTrue, reason: '${dry['error']}');
      expect(t.http.writes, isEmpty);
    });

    test('applying without a plan id is refused for every client', () async {
      final t = setup(before());
      for (final op in [
        'dns.apply',
        'email.setup',
        'app.setup',
        'app.teardown',
        'tunnel.route',
      ]) {
        final r = await last(t.api, req(op, origin: 'console'));
        expect(r['ok'], isFalse, reason: op);
        expect(r['error'], contains('needs plan_id'), reason: op);
      }
      final domain = await last(
        t.api,
        req('domain.add', params: {'provider': 'cloudflare'}),
      );
      expect(domain['error'], contains('needs plan_id'));
    });

    test(
      'domain.add on a Cloudflare environment needs approval without the provider param',
      () async {
        final t = setup(before());
        final mcp = await last(t.api, req('domain.add', origin: 'mcp'));
        expect(mcp['ok'], isFalse);
        expect(mcp['error'], contains('MCP clients may only plan'));
        final console = await last(
          t.api,
          req('domain.remove', origin: 'console'),
        );
        expect(console['error'], contains('needs plan_id'));
        expect(t.http.writes, isEmpty);
      },
    );

    test(
      'destroy plans on a remotely-managed tunnel and says to tear down first',
      () async {
        final t = setup(before(), dryRun: true);
        final op = t.api.destroy('production');
        final events = await op.events.toList();
        final r = await op.result;
        expect(r.ok, isTrue, reason: r.error);
        expect(
          events.whereType<LogLine>().map((e) => e.text).join('\n'),
          contains('podship app teardown --env production'),
        );
        expect(t.http.calls, isEmpty);
      },
    );

    test('the console applies the approved plan id', () async {
      final t = setup([...before(), ...writes()]);
      final plan = await last(t.api, req('dns.plan'));
      final id = ((plan['data'] as Map)['value'] as Map)['plan_id'];
      final r = await last(
        t.api,
        req('dns.apply', params: {'plan_id': id}, origin: 'console'),
      );
      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(t.http.writes.where((c) => c.method == 'POST'), hasLength(2));
    });

    test('every approval operation names a read-only plan operation', () {
      for (final o in operations.where((o) => o.approval != null)) {
        expect(o.mutating, isTrue, reason: o.name);
        if (o.planOperation != null) {
          expect(
            operationSpec(o.planOperation!)?.mutating,
            isFalse,
            reason: o.name,
          );
          expect(
            (o.inputSchema()['properties'] as Map).keys,
            contains('plan_id'),
            reason: o.name,
          );
        }
        expect(o.toJson()['approval'], o.approval);
      }
      expect(operationSpec('domain.add')!.needsApproval({}), isFalse);
      expect(
        operationSpec('domain.add')!.needsApproval({'provider': 'cloudflare'}),
        isTrue,
      );
    });

    test('requests carry the origin', () {
      final r = OperationRequest.fromJson(
        jsonDecode(jsonEncode(req('app.plan', origin: 'mcp').toJson()))
            as Map<String, Object?>,
      );
      expect(r.origin, 'mcp');
    });
  });

  group('cli', () {
    test('`podship tunnel --service …` still forwards a port', () {
      expect(
        compatArgs(['tunnel', '--service', 'postgres', '--port', '5432']),
        ['tunnel', 'forward', '--service', 'postgres', '--port', '5432'],
      );
      expect(compatArgs(['tunnel', 'list', '--env', 'production']), [
        'tunnel',
        'list',
        '--env',
        'production',
      ]);
      expect(compatArgs(['-C', 'x', 'tunnel', '-e', 'staging']), [
        '-C',
        'x',
        'tunnel',
        'forward',
        '-e',
        'staging',
      ]);
      expect(compatArgs(['deploy']), ['deploy']);
    });

    test('the new commands are registered', () {
      final r = PodshipRunner();
      for (final c in ['dns', 'tunnel', 'email', 'app', 'domain']) {
        expect(r.commands.keys, contains(c));
      }
      expect(
        r.commands['tunnel']!.subcommands.keys,
        containsAll(['list', 'route', 'unroute', 'create', 'forward']),
      );
      expect(
        r.commands['dns']!.subcommands.keys,
        containsAll(['plan', 'apply', 'list']),
      );
      expect(
        r.commands['email']!.subcommands.keys,
        containsAll(['status', 'setup', 'test']),
      );
      expect(
        r.commands['app']!.subcommands.keys,
        containsAll(['setup', 'teardown']),
      );
      expect(
        r.commands['domain']!.subcommands['add']!.argParser.options.keys,
        containsAll(['provider', 'plan', 'plan-id']),
      );
    });
  });
}
