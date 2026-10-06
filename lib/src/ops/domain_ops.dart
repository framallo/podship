// domain: routes from a hostname to an environment's loopback ports,
// through a Cloudflare Tunnel or Caddy (automatic TLS with Let's Encrypt).

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../config/config.dart';
import '../plan/plan.dart';
import '../api/tunnel.dart';
import '../remote/ssh.dart';
import 'context.dart';
import 'resolve.dart';
import 'scripts.dart';

/// Replaces the ingress rules of [host] in a cloudflared config with
/// [routes] (empty removes the host). New rules go before the catch-all.
String editTunnelConfig(String text, String host, List<ResolvedRoute> routes) {
  final ed = YamlEditor(text);
  final doc = loadYaml(text);
  final ingress = doc is YamlMap ? doc['ingress'] : null;
  if (ingress is! YamlList) {
    throw ConfigException('the tunnel config has no ingress list');
  }
  // Nothing to do when the host already has exactly these rules.
  final ordered0 = [
    ...routes.where((r) => r.path != null),
    ...routes.where((r) => r.path == null),
  ];
  final current = [
    for (final r in ingress)
      if (r is YamlMap && r['hostname'] == host)
        '${r['path'] ?? ''}|${r['service']}',
  ];
  final wanted = [
    for (final r in ordered0) '${r.path ?? ''}|http://localhost:${r.port}',
  ];
  if (current.join(',') == wanted.join(',')) return text;
  // Remove the host's rules, from the end so indexes stay valid.
  for (var i = ingress.length - 1; i >= 0; i--) {
    final r = ingress[i];
    if (r is YamlMap && r['hostname'] == host) ed.remove(['ingress', i]);
  }
  final now = ed.parseAt(['ingress']) as YamlList;
  var insertAt = now.length;
  for (var i = 0; i < now.length; i++) {
    final r = now[i];
    if (r is YamlMap && !r.containsKey('hostname')) {
      insertAt = i;
      break;
    }
  }
  // Rules with a path first: cloudflared takes the first match.
  final ordered = [
    ...routes.where((r) => r.path != null),
    ...routes.where((r) => r.path == null),
  ];
  for (final (i, r) in ordered.indexed) {
    ed.insertIntoList(
      ['ingress'],
      insertAt + i,
      {
        'hostname': host,
        if (r.path != null) 'path': r.path,
        'service': 'http://localhost:${r.port}',
      },
    );
  }
  return ed.toString();
}

/// The hosts and their services in a cloudflared config.
List<String> tunnelRules(String text) {
  final doc = loadYaml(text);
  final ingress = doc is YamlMap ? doc['ingress'] : null;
  if (ingress is! YamlList) return const [];
  return [
    for (final r in ingress)
      if (r is YamlMap)
        '${r['hostname'] ?? '*'}${r['path'] == null ? '' : ' ${r['path']}'} → ${r['service']}',
  ];
}

/// The Caddy site file of an environment: one block per domain.
String caddySite(String label, Map<String, List<ResolvedRoute>> domains) {
  final b = StringBuffer(
    '# Written by podship for $label. Caddy gets TLS certificates itself.\n',
  );
  for (final e in domains.entries) {
    b.writeln('${e.key} {');
    b.writeln('\tencode zstd gzip');
    for (final (i, r) in e.value.where((r) => r.path != null).indexed) {
      b.writeln('\t@r$i path_regexp ${r.path}');
      b.writeln('\thandle @r$i {\n\t\treverse_proxy 127.0.0.1:${r.port}\n\t}');
    }
    for (final r in e.value.where((r) => r.path == null)) {
      b.writeln('\thandle {\n\t\treverse_proxy 127.0.0.1:${r.port}\n\t}');
    }
    b.writeln('}');
  }
  return b.toString();
}

/// Restarts a service: systemd on Linux, launchd on macOS. launchd's
/// `kickstart -k` restarts in place, which keeps the gap short.
String restartService(String name) =>
    '''
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart ${shq(name)}
else
  launchctl kickstart -k gui/\$(id -u)/${shq(name)}
fi
''';

/// The DNS record a domain needs.
String dnsRecord(EnvConfig env, String host) => switch (env.proxy.kind) {
  ProxyKind.cloudflareTunnel =>
    'CNAME $host → ${env.proxy.tunnelId ?? '<tunnel-id>'}.cfargotunnel.com (proxied)',
  ProxyKind.caddy => 'A/AAAA $host → the public IP of ${env.host}',
  ProxyKind.none => 'none (no proxy configured)',
};

/// Plans `domain add` or `domain remove` for [hosts].
Plan planDomain(
  Ctx ctx,
  ResolvedEnv r,
  List<String> hosts, {
  bool remove = false,
}) {
  final env = r.env;
  final px = env.proxy;
  for (final h in hosts) {
    if (!remove && !r.domains.containsKey(h)) {
      throw ConfigException('add $h to environments.${env.name}.domains first');
    }
  }
  final stamp = r'$(date +%Y%m%d%H%M%S)';
  switch (px.kind) {
    case ProxyKind.none:
      throw ConfigException('environments.${env.name}.proxy.kind is none');
    case ProxyKind.cloudflareTunnel:
      final cfg =
          px.config ?? (throw ConfigException('proxy.config is required'));
      final svc = px.service ?? 'cloudflared';
      return Plan(
        '${remove ? 'remove' : 'route'} ${hosts.join(', ')} in the tunnel of ${env.host}',
        [
          ActionStep(
            'Edit $cfg',
            '${remove ? 'remove the rules of' : 'route'} ${hosts.join(', ')}'
                '${remove ? '' : ': ${[for (final h in hosts)
                        for (final x in r.domains[h]!) '${x.path ?? '/'} → ${x.port}'].join(', ')}'}; '
                'back up, validate, write, restart $svc (only when something changed)',
            () async {
              await TunnelRoutes(ctx.ssh, ctx.log).apply(
                tunnelTarget(env),
                [
                  for (final h in hosts)
                    RouteChange(h, remove ? const [] : r.domains[h]!),
                ],
                owner:
                    '{"tool":"podship","project":"${ctx.config.project}","env":"${env.name}"}',
                dns: !remove,
              );
            },
          ),
        ],
      );
    case ProxyKind.caddy:
      final site =
          px.config ?? '/etc/caddy/podship/${env.composeProject}.caddy';
      final svc = px.service ?? 'caddy';
      final keep = remove
          ? {
              for (final e in r.domains.entries)
                if (!hosts.contains(e.key)) e.key: e.value,
            }
          : r.domains;
      return Plan(
        '${remove ? 'remove' : 'route'} ${hosts.join(', ')} in Caddy on ${env.host}',
        [
          RemoteStep('Write $site, validate and reload', env.host, '''
${ctx.header(env)}[ -f ${shq(site)} ] && cp ${shq(site)} ${shq(site)}.bak.$stamp
${writeFile(site, caddySite('${ctx.config.project}/${env.name}', keep))}grep -q 'import /etc/caddy/podship/\\*.caddy' /etc/caddy/Caddyfile || echo 'import /etc/caddy/podship/*.caddy' >> /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl reload ${shq(svc)}
'''),
        ],
      );
  }
}

/// The cloudflared of [env], as a [TunnelTarget].
TunnelTarget tunnelTarget(EnvConfig env) => TunnelTarget(
  host: env.host,
  config:
      env.proxy.config ??
      (throw ConfigException(
        'environments.${env.name}.proxy.config is required',
      )),
  service: env.proxy.service ?? 'cloudflared',
  tunnelId: env.proxy.tunnelId ?? '<tunnel-id>',
  podshipHome: env.podshipHome,
  remotePath: env.remotePath,
  originCerts: env.proxy.originCerts,
);
