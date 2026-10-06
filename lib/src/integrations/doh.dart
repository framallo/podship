// Post-apply checks that do not trust the local resolver.
//
// After a record is created, a local resolver can keep the earlier
// negative answer for the zone's SOA minimum (30 minutes is common). So
// podship asks DNS over HTTPS (Cloudflare's resolver, JSON API) whether a
// name resolves, and checks the public URL with `curl --resolve`, pinned
// to an edge address that DoH returned.

import 'dart:io';

import 'http.dart';

class DohAnswer {
  DohAnswer(this.name, this.type, this.data, this.ttl);
  final String name;

  /// The numeric RR type (1 A, 5 CNAME, 28 AAAA, 16 TXT, 15 MX).
  final int type;
  final String data;
  final int ttl;
  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    'data': data,
    'ttl': ttl,
  };
}

class DohResolver {
  DohResolver({
    HttpTransport? transport,
    this.endpoint = 'https://cloudflare-dns.com/dns-query',
  }) : transport =
           transport ?? IoTransport(timeout: const Duration(seconds: 10));
  final HttpTransport transport;
  final String endpoint;

  /// The answers for [name] and [type] (`A`, `AAAA`, `CNAME`, `TXT`, `MX`).
  /// Empty for NXDOMAIN or no data.
  Future<List<DohAnswer>> query(String name, String type) async {
    final reply = await transport.send(
      HttpCall(
        'GET',
        Uri.parse(
          endpoint,
        ).replace(queryParameters: {'name': name, 'type': type}),
        headers: {'Accept': 'application/dns-json'},
      ),
    );
    if (reply.status != 200) {
      throw HttpException('DoH $name $type: HTTP ${reply.status}');
    }
    final j = reply.json as Map;
    return [
      for (final a in (j['Answer'] as List? ?? const []).cast<Map>())
        DohAnswer(
          '${a['name']}',
          (a['type'] as num).toInt(),
          '${a['data']}',
          (a['TTL'] as num? ?? 0).toInt(),
        ),
    ];
  }

  /// The IPv4 addresses [name] resolves to (following CNAMEs).
  Future<List<String>> addresses(String name) async => [
    for (final a in await query(name, 'A'))
      if (a.type == 1) a.data,
  ];

  /// Asks until [name] has an address, up to [attempts] times.
  Future<List<String>> waitForAddress(
    String name, {
    int attempts = 10,
    Duration interval = const Duration(seconds: 6),
  }) async {
    for (var i = 0; i < attempts; i++) {
      final a = await addresses(name);
      if (a.isNotEmpty) return a;
      if (i < attempts - 1) await Future<void>.delayed(interval);
    }
    return const [];
  }
}

/// The curl arguments that fetch [url] pinned to [ip], bypassing the local
/// resolver.
List<String> pinnedCurlArgs(String url, String ip) {
  final u = Uri.parse(url);
  final port = u.hasPort ? u.port : (u.scheme == 'http' ? 80 : 443);
  return [
    '-fsS',
    '-o',
    '/dev/null',
    '--max-time',
    '10',
    '--resolve',
    '${u.host}:$port:$ip',
    url,
  ];
}

/// Whether [url] answers 2xx when pinned to [ip].
Future<bool> pinnedHttpOk(String url, String ip) async {
  try {
    final r = await Process.run('curl', pinnedCurlArgs(url, ip));
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
