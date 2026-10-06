// Domains, DNS, tunnels, email and the whole app setup as change plans.
//
// Each function returns a [ChangeSet]: one plan, with before and after for
// every resource, that one approval applies. Server-side steps (registry,
// a local cloudflared config.yml, a Caddy site) are changes too, so
// `app setup` is one plan, and a failure undoes what ran before it.

import 'dart:async';

import 'package:yaml/yaml.dart';

import '../api/tunnel.dart';
import '../config/config.dart';
import '../integrations/changes.dart';
import '../integrations/cloudflare.dart';
import '../integrations/doh.dart';
import '../integrations/http.dart';
import '../integrations/planner.dart';
import '../integrations/secrets.dart';
import '../integrations/ses.dart';
import '../plan/plan.dart';
import '../server/registry.dart';
import 'context.dart';
import 'domain_ops.dart';
import 'resolve.dart';
import 'scripts.dart';
import 'secrets.dart';
import 'state.dart';

/// The outside services: where credentials and HTTP come from. A console
/// passes its own secret store; tests pass fixtures.
class Integrations {
  Integrations({
    SecretSource? secrets,
    HttpTransport? transport,
    DohResolver? doh,
  }) : secrets = secrets ?? SystemSecrets(),
       transport = transport ?? IoTransport(),
       doh = doh ?? DohResolver(transport: transport);
  final SecretSource secrets;
  final HttpTransport transport;
  final DohResolver doh;

  /// The Cloudflare client, or null without a token.
  CloudflareApi? cloudflare() {
    final t = secrets.read(cloudflareTokenKey);
    return t == null || t.isEmpty
        ? null
        : CloudflareApi(t, transport: transport);
  }

  CloudflareApi requireCloudflare() =>
      cloudflare() ??
      (throw Aborted(
        'no Cloudflare token: run `podship provider login cloudflare` (or set CLOUDFLARE_API_TOKEN)',
      ));

  bool get hasAws => secrets.read(awsCredentialsKey) != null;

  SesApi ses(String region) {
    final c = secrets.read(awsCredentialsKey);
    if (c == null) {
      throw Aborted(
        'no AWS credentials: run `podship provider login aws` (or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)',
      );
    }
    return SesApi(
      AwsCredentials.fromJson(c),
      region: region,
      transport: transport,
    );
  }
}

/// What a plan for one environment needs.
class EnvPlanning {
  EnvPlanning(
    this.ctx,
    this.env,
    this.integrations, {
    this.forceCloudflare = false,
  });
  final Ctx ctx;
  final EnvConfig env;
  final Integrations integrations;

  /// `--provider cloudflare`: use the Cloudflare API for DNS even when
  /// `dns.provider` is not set.
  final bool forceCloudflare;

  String get project => ctx.config.project;
  String get owner => ownerMark(project, env.name);

  bool get usesCloudflareDns =>
      forceCloudflare || env.dns.provider == DnsProvider.cloudflare;

  /// Whether Cloudflare is needed at all (DNS, a remote tunnel or Access).
  bool get needsCloudflare =>
      usesCloudflareDns ||
      env.proxy.remoteManaged ||
      env.domains.any((d) => d.access != null);

  CloudflarePlanner? _cf;
  CloudflarePlanner get cf => _cf ??= CloudflarePlanner(
    integrations.requireCloudflare(),
    project: project,
    env: env,
  );

  ResolvedEnv? _r;
  EnvState? _state;

  /// The resolved environment (ports from the server registry, over ssh).
  Future<ResolvedEnv> resolved() async {
    if (_r != null) return _r!;
    _state = await fetchState(ctx, env);
    return _r = resolveEnv(
      ctx.config,
      env,
      _state!.registry,
      listening: _state!.listening,
      now: DateTime.now().toUtc().toIso8601String(),
    );
  }

  List<String> hostsOr(List<String>? hosts) {
    final all = [for (final d in env.domains) d.host];
    if (hosts == null || hosts.isEmpty) return all;
    for (final h in hosts) {
      if (!all.contains(h)) {
        throw ConfigException(
          'add $h to environments.${env.name}.domains first',
        );
      }
    }
    return hosts;
  }

  // ------------------------------------------------------------- registry

  /// Registers the environment (ports, domains) in the server registry.
  Future<List<Change>> registry() async {
    final r = await resolved();
    final state = _state!;
    final had = state.registry.entries[r.entry.key];
    String ports(RegistryEntry e) =>
        e.ports.entries.map((x) => '${x.key}=${x.value}').join(' ');
    final summary = '${r.entry.key} on ${env.host}: ports ${ports(r.entry)}';
    if (had != null &&
        ports(had) == ports(r.entry) &&
        had.domains.join(',') == r.entry.domains.join(',')) {
      return [Change.unchanged('registry', r.entry.key, state: summary)];
    }
    return [
      Change(
        kind: had == null ? ChangeKind.create : ChangeKind.update,
        resource: 'registry',
        key: r.entry.key,
        before: had == null
            ? null
            : {'summary': '${had.key}: ports ${ports(had)}'},
        after: {'summary': summary},
        apply: () async {
          final before = state.registryText;
          final reg = Registry.parse(before)..put(r.entry);
          final next = reg.render();
          await ctx.executor.run(
            Plan('link', [
              RemoteStep(
                'Write the registry',
                env.host,
                ctx.header(env) +
                    installAssets(env) +
                    writeRegistry(env, before, next),
              ),
            ]),
          );
          if (had != null) return null;
          return Undo('remove ${r.entry.key} from the registry', () async {
            final reg2 = Registry.parse(next)..remove(r.entry.key);
            await ctx.executor.run(
              Plan('unlink', [
                RemoteStep(
                  'Write the registry',
                  env.host,
                  ctx.header(env) + writeRegistry(env, next, reg2.render()),
                ),
              ]),
            );
          });
        },
      ),
    ];
  }

  // -------------------------------------------------------------- routing

  /// The proxy routes of [hosts]: tunnel ingress (API or config.yml) or the
  /// Caddy site. [remove] takes the hosts out.
  Future<List<Change>> routes(List<String> hosts, {bool remove = false}) async {
    final r = await resolved();
    final wanted = {
      for (final h in hosts) h: remove ? <ResolvedRoute>[] : r.domains[h]!,
    };
    switch (env.proxy.kind) {
      case ProxyKind.none:
        return const [];
      case ProxyKind.cloudflareTunnel:
        if (env.proxy.remoteManaged) return cf.tunnelIngress(wanted);
        return _localTunnel(wanted);
      case ProxyKind.caddy:
        return _caddy(r, hosts, remove);
    }
  }

  Future<List<Change>> _localTunnel(
    Map<String, List<ResolvedRoute>> wanted,
  ) async {
    final target = tunnelTarget(env);
    final text = await readRemote(ctx, env, target.config);
    if (text.trim().isEmpty) {
      throw ConfigException(
        '${target.config} is empty or missing on ${env.host}',
      );
    }
    final out = <Change>[];
    for (final e in wanted.entries) {
      final before = configRoutes(text, e.key);
      String show(List<ResolvedRoute> rs) => rs.isEmpty
          ? 'no rules'
          : [
              for (final x in [
                ...rs.where((x) => x.path != null),
                ...rs.where((x) => x.path == null),
              ])
                '${e.key}${x.path == null ? '' : ' ${x.path}'} → http://localhost:${x.port}',
            ].join('; ');
      final key = '${e.key} in ${target.config} on ${env.host}';
      if (show(before) == show(e.value)) {
        out.add(
          Change.unchanged('tunnel_config_file', key, state: show(e.value)),
        );
        continue;
      }
      out.add(
        Change(
          kind: before.isEmpty
              ? ChangeKind.create
              : e.value.isEmpty
              ? ChangeKind.delete
              : ChangeKind.update,
          resource: 'tunnel_config_file',
          key: key,
          before: before.isEmpty ? null : {'summary': show(before)},
          after: e.value.isEmpty ? null : {'summary': show(e.value)},
          note:
              'backed up, validated with cloudflared, restart of ${target.service}',
          apply: () async {
            final routes = TunnelRoutes(ctx.ssh, ctx.log);
            await routes.apply(
              target,
              [RouteChange(e.key, e.value)],
              owner: owner,
              dns: false,
            );
            return Undo(
              'restore the rules of ${e.key} in ${target.config}',
              () => routes
                  .apply(
                    target,
                    [RouteChange(e.key, before)],
                    owner: owner,
                    dns: false,
                  )
                  .then((_) {}),
            );
          },
        ),
      );
    }
    return out;
  }

  Future<List<Change>> _caddy(
    ResolvedEnv r,
    List<String> hosts,
    bool remove,
  ) async {
    final site =
        env.proxy.config ?? '/etc/caddy/podship/${env.composeProject}.caddy';
    final keep = {
      for (final e in r.domains.entries)
        if (!remove || !hosts.contains(e.key)) e.key: e.value,
    };
    final next = caddySite('$project/${env.name}', keep);
    final now = await readRemote(ctx, env, site);
    if (now == next) {
      return [
        Change.unchanged('caddy_site', site, state: keep.keys.join(', ')),
      ];
    }
    final plan = planDomain(ctx, r, hosts, remove: remove);
    return [
      Change(
        kind: now.isEmpty ? ChangeKind.create : ChangeKind.update,
        resource: 'caddy_site',
        key: '$site on ${env.host}',
        before: now.isEmpty
            ? null
            : {'summary': 'serves ${caddyHosts(now).join(', ')}'},
        after: {
          'summary':
              'serves ${keep.keys.join(', ')} (Caddy gets the certificates)',
        },
        apply: () async {
          await ctx.executor.run(plan);
          return null;
        },
      ),
    ];
  }

  // ------------------------------------------------------------------ DNS

  /// DNS records of [hosts] through Cloudflare, or a check that names the
  /// record to create by hand.
  Future<(List<Change>, List<PlanCheck>)> dns(
    List<String> hosts, {
    bool remove = false,
  }) async {
    if (!usesCloudflareDns) {
      return (
        const <Change>[],
        [
          if (!remove)
            for (final h in hosts)
              PlanCheck(
                'DNS $h',
                false,
                'create by hand: ${dnsRecord(env, h)}',
              ),
        ],
      );
    }
    return (await cf.hostRecords(hosts, remove: remove), const <PlanCheck>[]);
  }

  Future<List<Change>> access(List<String> hosts, {bool remove = false}) async {
    if (!env.domains.any((d) => hosts.contains(d.host) && d.access != null)) {
      return const [];
    }
    return cf.access(hosts, remove: remove);
  }

  Future<List<PlanCheck>> tls(List<String> hosts) async {
    if (!usesCloudflareDns || env.proxy.kind != ProxyKind.cloudflareTunnel) {
      return [
        if (env.proxy.kind == ProxyKind.caddy)
          for (final h in hosts)
            PlanCheck(
              'TLS $h',
              true,
              'Caddy gets a Let\'s Encrypt certificate',
            ),
      ];
    }
    return cf.tls(hosts);
  }

  // ---------------------------------------------------------------- email

  EmailPlanner email() {
    final e =
        env.email ??
        (throw ConfigException('environments.${env.name}.email is not set'));
    CloudflarePlanner? dnsPlanner;
    if (usesCloudflareDns && integrations.cloudflare() != null) dnsPlanner = cf;
    return EmailPlanner(
      integrations.ses(e.region),
      email: e,
      project: project,
      env: env.name,
      dns: dnsPlanner,
    );
  }
}

/// The routes of [host] in a cloudflared config.yml (services of the form
/// `http://localhost:<port>`).
List<ResolvedRoute> configRoutes(String text, String host) {
  final doc = loadYaml(text);
  final ingress = doc is YamlMap ? doc['ingress'] : null;
  if (ingress is! YamlList) return const [];
  return [
    for (final r in ingress)
      if (r is YamlMap && r['hostname'] == host)
        if (RegExp(r':(\d+)/?$').firstMatch('${r['service']}') case final m?)
          ResolvedRoute(r['path'] as String?, int.parse(m[1]!)),
  ];
}

/// The site names in a Caddy file podship wrote.
List<String> caddyHosts(String text) => [
  for (final m in RegExp(r'^(\S+) \{$', multiLine: true).allMatches(text))
    m[1]!,
];

/// `domain add|remove` (with Cloudflare): routes, DNS records and Access.
Future<ChangeSet> planDomainChanges(
  EnvPlanning p,
  List<String>? hosts, {
  bool remove = false,
}) async {
  final list = p.hostsOr(hosts);
  final routes = await p.routes(list, remove: remove);
  final (dns, dnsChecks) = await p.dns(list, remove: remove);
  final access = p.integrations.cloudflare() == null && !p.needsCloudflare
      ? const <Change>[]
      : await p.access(list, remove: remove);
  final tls = remove ? const <PlanCheck>[] : await p.tls(list);
  // Removing: DNS first, so traffic stops before the route goes away.
  return ChangeSet(
    '${remove ? 'remove' : 'add'} ${list.join(', ')} (${p.project}/${p.env.name})',
    remove ? [...access, ...dns, ...routes] : [...routes, ...dns, ...access],
    checks: [...dnsChecks, ...tls],
  );
}

/// `app setup`: registry, routes, DNS, Access, TLS check, email.
Future<ChangeSet> planAppSetup(EnvPlanning p) async {
  final hosts = p.hostsOr(null);
  final registry = await p.registry();
  final domains = hosts.isEmpty
      ? ChangeSet('', const [])
      : await planDomainChanges(p, hosts);
  var set = ChangeSet('app setup ${p.project}/${p.env.name} on ${p.env.host}', [
    ...registry,
    ...domains.changes,
  ], checks: domains.checks);
  if (p.env.email != null) {
    if (p.integrations.hasAws) {
      set = set + await p.email().plan();
    } else {
      set =
          set +
          ChangeSet(
            '',
            const [],
            checks: [
              PlanCheck(
                'email',
                false,
                'no AWS credentials: run `podship provider login aws`',
              ),
            ],
          );
    }
  }
  return set;
}

/// `app teardown`: the reverse of setup, for what points to this
/// environment. The registry entry stays (`podship destroy` removes the
/// environment itself). The SES identity goes only with [email] and only
/// when it carries this environment's tag.
Future<ChangeSet> planAppTeardown(EnvPlanning p, {bool email = false}) async {
  final hosts = p.hostsOr(null);
  var set = hosts.isEmpty
      ? ChangeSet('', const [])
      : await planDomainChanges(p, hosts, remove: true);
  set = ChangeSet(
    'app teardown ${p.project}/${p.env.name}',
    set.changes,
    checks: set.checks,
  );
  if (email && p.env.email != null) {
    set = set + await p.email().teardown();
  }
  return set;
}

/// After an apply: do the names resolve (over DoH, not the local resolver,
/// which may cache the earlier NXDOMAIN), and does the public health URL
/// answer when pinned to an edge address?
Future<List<PlanCheck>> postApplyChecks(
  EnvPlanning p,
  ResolvedEnv r, {
  int attempts = 10,
  Duration interval = const Duration(seconds: 6),
}) async {
  final out = <PlanCheck>[];
  final hosts = p.hostsOr(null);
  final ips = <String, List<String>>{};
  for (final h in hosts) {
    try {
      final a = await p.integrations.doh.waitForAddress(
        h,
        attempts: attempts,
        interval: interval,
      );
      ips[h] = a;
      out.add(
        PlanCheck(
          'DNS $h',
          a.isNotEmpty,
          a.isEmpty
              ? 'no address yet over DoH'
              : 'resolves to ${a.join(' ')} (DoH)',
        ),
      );
    } catch (e) {
      out.add(PlanCheck('DNS $h', false, 'DoH failed: $e'));
    }
  }
  final url = r.publicHealthUrl;
  if (url != null) {
    final host = Uri.parse(url).host;
    final ip = (ips[host] ?? const []).firstOrNull;
    if (ip == null) {
      out.add(
        PlanCheck(
          'health $url',
          false,
          'not checked: $host has no address yet',
        ),
      );
    } else {
      final ok = await pinnedHttpOk(url, ip);
      out.add(
        PlanCheck(
          'health $url',
          ok,
          ok
              ? 'answers through $ip'
              : 'no 2xx answer through $ip (deploy the app, or wait for the tunnel)',
        ),
      );
    }
  }
  return out;
}
