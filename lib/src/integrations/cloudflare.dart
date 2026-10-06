// Cloudflare API v4 with an API token.
//
// The token needs (see the README, "Cloudflare and SES"):
//   Zone  · DNS · Edit                       DNS records
//   Zone  · Zone · Read                      find the zone of a hostname
//   Account · Cloudflare Tunnel · Edit       tunnels and their ingress
//   Account · Access: Apps and Policies · Edit   (optional) Access apps
//
// The account id comes from the zone (every zone names its account), so
// the token needs no account-level read permission for it.

import 'dart:convert';

import 'http.dart';

/// An API error, with Cloudflare's error codes and messages.
class CloudflareException implements Exception {
  CloudflareException(this.status, this.message, {this.codes = const []});
  final int status;
  final String message;
  final List<int> codes;
  @override
  String toString() => 'Cloudflare: $message (HTTP $status)';
}

class CfZone {
  CfZone({
    required this.id,
    required this.name,
    required this.accountId,
    this.status = 'active',
  });
  factory CfZone.fromJson(Map j) => CfZone(
    id: '${j['id']}',
    name: '${j['name']}',
    accountId: '${(j['account'] as Map?)?['id'] ?? ''}',
    status: '${j['status'] ?? ''}',
  );
  final String id;
  final String name;
  final String accountId;
  final String status;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'account_id': accountId,
    'status': status,
  };
}

/// A DNS record.
class CfDnsRecord {
  CfDnsRecord({
    this.id,
    required this.type,
    required this.name,
    required this.content,
    this.proxied = false,
    this.ttl = 1,
    this.priority,
    this.comment,
  });
  factory CfDnsRecord.fromJson(Map j) => CfDnsRecord(
    id: j['id'] as String?,
    type: '${j['type']}',
    name: '${j['name']}',
    content: '${j['content']}',
    proxied: j['proxied'] == true,
    ttl: (j['ttl'] as num? ?? 1).toInt(),
    priority: (j['priority'] as num?)?.toInt(),
    comment: j['comment'] as String?,
  );

  final String? id;
  final String type;
  final String name;
  final String content;
  final bool proxied;

  /// 1 means automatic.
  final int ttl;

  /// MX only.
  final int? priority;

  /// podship marks the records it creates: `podship <project>/<env>`.
  final String? comment;

  CfDnsRecord withId(String id) => CfDnsRecord(
    id: id,
    type: type,
    name: name,
    content: content,
    proxied: proxied,
    ttl: ttl,
    priority: priority,
    comment: comment,
  );

  /// Whether [other] has the same type, name, content, proxy and priority
  /// (the comment and TTL do not count as a difference).
  bool sameAs(CfDnsRecord other) =>
      type == other.type &&
      name.toLowerCase() == other.name.toLowerCase() &&
      _norm(content) == _norm(other.content) &&
      proxied == other.proxied &&
      (type != 'MX' || priority == other.priority);

  static String _norm(String c) => c
      .toLowerCase()
      .replaceAll(RegExp(r'^"|"$'), '')
      .replaceAll(RegExp(r'\.$'), '');

  /// The request body for create and update.
  Map<String, Object?> body() => {
    'type': type,
    'name': name,
    'content': content,
    if (type == 'A' || type == 'AAAA' || type == 'CNAME') 'proxied': proxied,
    'ttl': ttl,
    'priority': ?priority,
    'comment': ?comment,
  };

  Map<String, Object?> toJson() => {'id': ?id, ...body()};

  /// One line: `CNAME app.example.com → abc.cfargotunnel.com (proxied)`.
  String describe() =>
      '$type $name → ${priority == null ? '' : '$priority '}$content${proxied ? ' (proxied)' : ''}';
}

/// A Cloudflare Tunnel.
class CfTunnel {
  CfTunnel({
    required this.id,
    required this.name,
    required this.status,
    required this.remoteConfig,
    this.connections = 0,
  });
  factory CfTunnel.fromJson(Map j) => CfTunnel(
    id: '${j['id']}',
    name: '${j['name']}',
    status: '${j['status'] ?? ''}',
    remoteConfig: j['remote_config'] == true,
    connections: (j['connections'] as List? ?? const []).length,
  );
  final String id;
  final String name;

  /// `healthy`, `degraded`, `down` or `inactive`.
  final String status;

  /// Whether the tunnel's ingress is managed in Cloudflare (not in a
  /// config.yml on the host).
  final bool remoteConfig;
  final int connections;

  String get cname => '$id.cfargotunnel.com';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'status': status,
    'managed': remoteConfig ? 'remote' : 'local',
    'connections': connections,
  };
}

/// One ingress rule of a remotely-managed tunnel.
class CfIngressRule {
  CfIngressRule({this.hostname, this.path, required this.service, this.extra});
  factory CfIngressRule.fromJson(Map j) => CfIngressRule(
    hostname: j['hostname'] as String?,
    path: j['path'] as String?,
    service: '${j['service']}',
    extra: {
      for (final e in j.entries)
        if (!const ['hostname', 'path', 'service'].contains(e.key))
          '${e.key}': e.value,
    },
  );
  final String? hostname;
  final String? path;
  final String service;

  /// Other keys (originRequest…), kept as they are.
  final Map<String, Object?>? extra;

  Map<String, Object?> toJson() => {
    'hostname': ?hostname,
    'path': ?path,
    'service': service,
    ...?extra,
  };

  String describe() =>
      '${hostname ?? '*'}${path == null ? '' : ' $path'} → $service';
}

/// The configuration of a remotely-managed tunnel.
class CfTunnelConfig {
  CfTunnelConfig({
    required this.ingress,
    this.version = 0,
    this.source = 'cloudflare',
    this.rest = const {},
  });
  factory CfTunnelConfig.fromJson(Map j) {
    final config = (j['config'] as Map?) ?? const {};
    return CfTunnelConfig(
      ingress: [
        for (final r in (config['ingress'] as List? ?? const []))
          CfIngressRule.fromJson(r as Map),
      ],
      version: (j['version'] as num? ?? 0).toInt(),
      source: '${j['source'] ?? 'cloudflare'}',
      rest: {
        for (final e in config.entries)
          if (e.key != 'ingress') '${e.key}': e.value,
      },
    );
  }
  final List<CfIngressRule> ingress;
  final int version;

  /// `cloudflare` (managed in the dashboard or API) or `local` (a
  /// config.yml on the host; podship must not overwrite it through the API).
  final String source;

  /// Other config keys (warp-routing, originRequest), kept as they are.
  final Map<String, Object?> rest;

  Map<String, Object?> body() => {
    'config': {
      ...rest,
      'ingress': [for (final r in ingress) r.toJson()],
    },
  };

  /// The rules of [hostname].
  List<CfIngressRule> rulesOf(String hostname) => [
    for (final r in ingress)
      if (r.hostname == hostname) r,
  ];

  /// A copy with [hostname]'s rules replaced by [rules] (none removes the
  /// hostname). Rules with a path go first; new rules go before the
  /// catch-all, which stays last (and is added when missing).
  CfTunnelConfig withHost(String hostname, List<CfIngressRule> rules) {
    final kept = [
      for (final r in ingress)
        if (r.hostname != hostname) r,
    ];
    final catchAll = kept.where((r) => r.hostname == null).toList();
    final named = kept.where((r) => r.hostname != null).toList();
    final ordered = [
      ...rules.where((r) => r.path != null),
      ...rules.where((r) => r.path == null),
    ];
    return CfTunnelConfig(
      ingress: [
        ...named,
        ...ordered,
        ...(catchAll.isEmpty
            ? [CfIngressRule(service: 'http_status:404')]
            : catchAll),
      ],
      version: version,
      source: source,
      rest: rest,
    );
  }
}

/// An Access application.
class CfAccessApp {
  CfAccessApp({required this.id, required this.name, required this.domain});
  factory CfAccessApp.fromJson(Map j) => CfAccessApp(
    id: '${j['id']}',
    name: '${j['name']}',
    domain: '${j['domain']}',
  );
  final String id;
  final String name;
  final String domain;
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'domain': domain};
}

class CloudflareApi {
  CloudflareApi(
    this._token, {
    HttpTransport? transport,
    this.base = 'https://api.cloudflare.com/client/v4',
  }) : transport = transport ?? IoTransport();
  final String _token;
  final HttpTransport transport;
  final String base;

  /// A client that can only read (for plans).
  CloudflareApi readOnly() => CloudflareApi(
    _token,
    transport: ReadOnlyTransport(transport),
    base: base,
  );

  Future<({Object? result, Map? info})> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final url = Uri.parse(
      '$base$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final reply = await transport.send(
      HttpCall(
        method,
        url,
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    Map j;
    try {
      j = (reply.json as Map?) ?? const {};
    } catch (_) {
      throw CloudflareException(reply.status, 'not JSON: $method $path');
    }
    if (reply.status >= 400 || j['success'] == false) {
      final errors = (j['errors'] as List? ?? const []).cast<Map>();
      throw CloudflareException(
        reply.status,
        errors.isEmpty
            ? '$method $path failed'
            : errors.map((e) => '${e['message']} [${e['code']}]').join('; '),
        codes: [for (final e in errors) (e['code'] as num? ?? 0).toInt()],
      );
    }
    return (result: j['result'], info: j['result_info'] as Map?);
  }

  /// Every page of a list.
  Future<List<Map>> _list(String path, [Map<String, String>? query]) async {
    final out = <Map>[];
    for (var page = 1; ; page++) {
      final r = await _call(
        'GET',
        path,
        query: {...?query, 'page': '$page', 'per_page': '50'},
      );
      out.addAll((r.result as List? ?? const []).cast<Map>());
      final total = (r.info?['total_pages'] as num?)?.toInt() ?? 1;
      if (page >= total) return out;
    }
  }

  /// Checks the token. Returns its status (`active`).
  Future<String> verifyToken() async =>
      '${((await _call('GET', '/user/tokens/verify')).result as Map)['status']}';

  Future<List<CfZone>> zones({String? name}) async => [
    for (final z in await _list('/zones', {'name': ?name})) CfZone.fromJson(z),
  ];

  /// The zone that holds [hostname]: the longest zone name it ends with.
  /// [zoneName] skips the search.
  /// The zone that holds [hostname]: the longest zone name it equals or
  /// ends with, among the zones the token can read. Refuses when none
  /// matches, or when [zoneName] does not hold [hostname].
  ///
  /// This matters: `cloudflared tunnel route dns` with the origin cert of
  /// zone A, given a hostname of zone B, silently creates
  /// `<hostname>.<zoneA>`. podship never guesses a zone.
  Future<CfZone> zoneFor(String hostname, {String? zoneName}) async {
    final host = hostname.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    bool holds(String zone) => host == zone || host.endsWith('.$zone');
    if (zoneName != null && !holds(zoneName.toLowerCase())) {
      throw CloudflareException(
        400,
        '$hostname is not in the zone $zoneName (dns.zone); refusing to create '
        'a record there',
      );
    }
    final labels = host.split('.');
    final candidates = zoneName != null
        ? [zoneName.toLowerCase()]
        : [
            for (var i = 0; i < labels.length - 1; i++)
              labels.sublist(i).join('.'),
          ];
    for (final c in candidates) {
      // Only an exact name counts, whatever the API's filter returns.
      final z = (await zones(name: c)).where((z) => z.name.toLowerCase() == c);
      if (z.isNotEmpty) return z.first;
    }
    throw CloudflareException(
      404,
      'no zone for $hostname among the zones this token can read '
      '(tried ${candidates.join(', ')}); add the zone to the token, or the '
      'domain to Cloudflare',
    );
  }

  Future<List<CfDnsRecord>> dnsRecords(
    String zoneId, {
    String? name,
    String? type,
  }) async => [
    for (final r in await _list('/zones/$zoneId/dns_records', {
      'name': ?name,
      'type': ?type,
    }))
      CfDnsRecord.fromJson(r),
  ];

  Future<CfDnsRecord> createDns(String zoneId, CfDnsRecord r) async =>
      CfDnsRecord.fromJson(
        (await _call(
              'POST',
              '/zones/$zoneId/dns_records',
              body: r.body(),
            )).result
            as Map,
      );

  Future<CfDnsRecord> updateDns(
    String zoneId,
    String id,
    CfDnsRecord r,
  ) async => CfDnsRecord.fromJson(
    (await _call(
          'PUT',
          '/zones/$zoneId/dns_records/$id',
          body: r.body(),
        )).result
        as Map,
  );

  Future<void> deleteDns(String zoneId, String id) =>
      _call('DELETE', '/zones/$zoneId/dns_records/$id');

  /// Whether Universal SSL is on for the zone (the edge certificate that
  /// covers the apex and one level of subdomains).
  Future<bool> universalSsl(String zoneId) async =>
      ((await _call('GET', '/zones/$zoneId/ssl/universal/settings')).result
          as Map)['enabled'] ==
      true;

  Future<List<CfTunnel>> tunnels(String accountId) async => [
    for (final t in await _list('/accounts/$accountId/cfd_tunnel', {
      'is_deleted': 'false',
    }))
      CfTunnel.fromJson(t),
  ];

  Future<CfTunnel> tunnel(String accountId, String id) async =>
      CfTunnel.fromJson(
        (await _call('GET', '/accounts/$accountId/cfd_tunnel/$id')).result
            as Map,
      );

  /// Creates a remotely-managed tunnel. Its connector token is not
  /// returned: fetch it on the server that runs the connector.
  Future<CfTunnel> createTunnel(String accountId, String name) async =>
      CfTunnel.fromJson(
        (await _call(
              'POST',
              '/accounts/$accountId/cfd_tunnel',
              body: {'name': name, 'config_src': 'cloudflare'},
            )).result
            as Map,
      );

  Future<CfTunnelConfig> tunnelConfig(String accountId, String id) async {
    final r = await _call(
      'GET',
      '/accounts/$accountId/cfd_tunnel/$id/configurations',
    );
    return CfTunnelConfig.fromJson((r.result as Map?) ?? const {});
  }

  Future<CfTunnelConfig> putTunnelConfig(
    String accountId,
    String id,
    CfTunnelConfig config,
  ) async {
    final r = await _call(
      'PUT',
      '/accounts/$accountId/cfd_tunnel/$id/configurations',
      body: config.body(),
    );
    return CfTunnelConfig.fromJson((r.result as Map?) ?? const {});
  }

  Future<List<CfAccessApp>> accessApps(String accountId) async => [
    for (final a in await _list('/accounts/$accountId/access/apps'))
      CfAccessApp.fromJson(a),
  ];

  /// A self-hosted Access app for [domain] that lets in [emails] (and
  /// everyone at [emailDomains]).
  Future<CfAccessApp> createAccessApp(
    String accountId, {
    required String name,
    required String domain,
    List<String> emails = const [],
    List<String> emailDomains = const [],
    String sessionDuration = '24h',
  }) async => CfAccessApp.fromJson(
    (await _call(
          'POST',
          '/accounts/$accountId/access/apps',
          body: accessAppBody(
            name: name,
            domain: domain,
            emails: emails,
            emailDomains: emailDomains,
            sessionDuration: sessionDuration,
          ),
        )).result
        as Map,
  );

  Future<void> deleteAccessApp(String accountId, String id) =>
      _call('DELETE', '/accounts/$accountId/access/apps/$id');
}

/// The body of an Access app create, with one inline allow policy.
Map<String, Object?> accessAppBody({
  required String name,
  required String domain,
  List<String> emails = const [],
  List<String> emailDomains = const [],
  String sessionDuration = '24h',
}) => {
  'name': name,
  'domain': domain,
  'type': 'self_hosted',
  'session_duration': sessionDuration,
  'app_launcher_visible': false,
  'policies': [
    {
      'name': 'podship: allowed people',
      'decision': 'allow',
      'precedence': 1,
      'include': [
        for (final e in emails)
          {
            'email': {'email': e},
          },
        for (final d in emailDomains)
          {
            'email_domain': {'domain': d},
          },
      ],
    },
  ],
};
