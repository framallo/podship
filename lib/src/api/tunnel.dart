// Cloudflare Tunnel routes as an API: add or remove "hostname → local port"
// rules on a server's cloudflared, safely.
//
// - One editor at a time per server: the lock folder
//   `<podship_home>/locks/cloudflared` (mkdir, so it works on macOS too).
//   Every client takes it, podship's `domain add` as well as other tools
//   that use this library, and waits for it.
// - The config is backed up, edited in memory (comments kept), validated
//   with `cloudflared tunnel ingress validate`, written, and the tunnel is
//   restarted only when something changed (`systemctl restart` on Linux,
//   `launchctl kickstart -k` on macOS: the shortest blip).
// - DNS: with an origin certificate for the hostname's zone, podship runs
//   `cloudflared tunnel route dns`; otherwise it reports the CNAME to add.

import 'dart:convert';

import '../ops/domain_ops.dart';
import '../ops/resolve.dart';
import '../remote/ssh.dart';
import '../util/log.dart';

/// A cloudflared on a server.
class TunnelTarget {
  TunnelTarget({
    required this.host,
    required this.config,
    required this.service,
    required this.tunnelId,
    this.podshipHome = '/srv/podship',
    this.remotePath,
    this.originCerts = const {},
  });

  /// The ssh destination.
  final String host;

  /// The cloudflared config file on the server.
  final String config;

  /// The systemd unit or launchd label that runs the tunnel.
  final String service;
  final String tunnelId;
  final String podshipHome;

  /// A directory added to the front of PATH on the server.
  final String? remotePath;

  /// Origin certificates by zone, like `{'example.com': '/root/.cloudflared/cert.pem'}`,
  /// for `route dns`.
  final Map<String, String> originCerts;

  String get lockDir => '$podshipHome/locks/cloudflared';

  /// The CNAME a hostname needs.
  String cname(String hostname) =>
      'CNAME $hostname → $tunnelId.cfargotunnel.com (proxied)';
}

/// A route change: [routes] for [hostname], or none to remove it.
class RouteChange {
  RouteChange(this.hostname, this.routes);
  final String hostname;
  final List<ResolvedRoute> routes;
}

/// What a change did.
class RouteResult {
  RouteResult({required this.changed, required this.dns});

  /// Whether the config changed (and the tunnel restarted).
  final bool changed;

  /// By hostname: `created`, `exists`, or the record to add by hand.
  final Map<String, String> dns;

  Map<String, Object?> toJson() => {'changed': changed, 'dns': dns};
}

class TunnelRoutes {
  TunnelRoutes(this.ssh, this.log);
  final Ssh ssh;
  final Log log;

  String _header(TunnelTarget t) =>
      'set -euo pipefail\n${t.remotePath == null ? '' : 'export PATH=${shq(t.remotePath!)}:"\$PATH"\n'}';

  /// Takes the cloudflared lock of [t], waiting up to [wait]. A lock older
  /// than 10 minutes is taken over.
  Future<void> lock(
    TunnelTarget t,
    String owner, {
    Duration wait = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(wait);
    while (true) {
      final out = await ssh.capture(t.host, '''
${_header(t)}mkdir -p ${shq('${t.podshipHome}/locks')}
if mkdir ${shq(t.lockDir)} 2>/dev/null; then
  cat > ${shq('${t.lockDir}/owner')}; echo OK
elif [ -n "\$(find ${shq(t.lockDir)} -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
  rm -rf ${shq(t.lockDir)} && mkdir ${shq(t.lockDir)} && cat > ${shq('${t.lockDir}/owner')} && echo OK
else
  echo "BUSY \$(cat ${shq('${t.lockDir}/owner')} 2>/dev/null)"
fi
''', stdin: utf8.encode(owner));
      if (out.trim() == 'OK') return;
      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'the cloudflared config on ${t.host} is locked by ${out.trim().replaceFirst('BUSY ', '')}',
        );
      }
      log.info(
        'waiting for the cloudflared lock on ${t.host} (${out.trim().replaceFirst('BUSY ', '')})',
      );
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> unlock(TunnelTarget t) =>
      ssh.capture(t.host, 'rm -rf ${shq(t.lockDir)}');

  /// Applies [changes] to [t] under the lock. With [dryRun], computes the
  /// new config and reports, without writing.
  Future<RouteResult> apply(
    TunnelTarget t,
    List<RouteChange> changes, {
    String owner = 'podship',
    bool dryRun = false,
    bool dns = true,
  }) async {
    if (!dryRun) await lock(t, owner);
    try {
      final before = await ssh.capture(
        t.host,
        '${_header(t)}cat ${shq(t.config)}',
      );
      var after = before;
      for (final c in changes) {
        after = editTunnelConfig(after, c.hostname, c.routes);
      }
      final changed = after != before;
      if (changed && !dryRun) {
        final stamp = r'$(date +%Y%m%d%H%M%S)';
        await ssh.capture(t.host, '''
${_header(t)}cp ${shq(t.config)} ${shq(t.config)}.bak.$stamp
new=${shq('${t.config}.podship-new')}
cat > "\$new"
cloudflared tunnel --config "\$new" ingress validate
mv -f "\$new" ${shq(t.config)}
${restartService(t.service)}sleep 3
''', stdin: utf8.encode(after));
        log.info('updated ${t.config} on ${t.host} and restarted ${t.service}');
      } else if (!changed) {
        log.info('the tunnel on ${t.host} already has these routes');
      }
      final dnsOut = <String, String>{};
      for (final c in changes.where((c) => c.routes.isNotEmpty)) {
        dnsOut[c.hostname] = dns && !dryRun
            ? await _routeDns(t, c.hostname)
            : t.cname(c.hostname);
      }
      return RouteResult(changed: changed, dns: dnsOut);
    } finally {
      if (!dryRun) await unlock(t);
    }
  }

  /// Creates the DNS record with the zone's origin certificate, when there
  /// is one. Returns `created`, `exists`, or the record to add by hand.
  Future<String> _routeDns(TunnelTarget t, String hostname) async {
    final cert = originCertFor(t.originCerts, hostname);
    if (cert == null) return t.cname(hostname);
    final r = await ssh.captureResult(
      t.host,
      '${_header(t)}cloudflared tunnel --origincert ${shq(cert)} route dns ${shq(t.tunnelId)} ${shq(hostname)} 2>&1',
    );
    final out = '${r.stdout}${r.stderr}';
    if (r.exitCode != 0) {
      log.warn(
        'route dns for $hostname failed: ${out.trim().split('\n').last}',
      );
      return t.cname(hostname);
    }
    final made = routeDnsName(out);
    if (made != null && made != hostname.toLowerCase()) {
      // cloudflared appends the cert's zone to a name outside it.
      log.error(
        'cloudflared created $made instead of $hostname: the origin cert is '
        'not for the zone of $hostname. Delete $made in Cloudflare, fix '
        'proxy.origin_certs, or use dns.provider: cloudflare.',
      );
      return t.cname(hostname);
    }
    return out.contains('already') ? 'exists' : 'created';
  }
}

/// The origin certificate for [hostname]: the longest zone key it equals
/// or ends with, or null (never a cert for another zone).
String? originCertFor(Map<String, String> certs, String hostname) {
  final h = hostname.toLowerCase();
  String? best;
  var bestLen = -1;
  for (final e in certs.entries) {
    final z = e.key.toLowerCase();
    if ((h == z || h.endsWith('.$z')) && z.length > bestLen) {
      best = e.value;
      bestLen = z.length;
    }
  }
  return best;
}

/// The record name in the output of `cloudflared tunnel route dns`
/// ("Added CNAME x.example.com which will route to this tunnel"), or null.
String? routeDnsName(String output) {
  final m =
      RegExp(
        r'(?:Added CNAME|CNAME record for) (\S+?)\.? ',
      ).firstMatch(output) ??
      RegExp(r'(\S+?)\.? is already configured to route').firstMatch(output);
  return m?.group(1)?.toLowerCase();
}
