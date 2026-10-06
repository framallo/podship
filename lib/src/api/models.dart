// Typed results of the read operations. Each has toJson for `--json`.

import 'dart:convert';

import '../ops/state.dart';
import '../server/registry.dart';

Map<String, Object?> _decode(String s) {
  try {
    final j = jsonDecode(s);
    return j is Map<String, Object?> ? j : const {};
  } catch (_) {
    return const {};
  }
}

/// One container of a compose project.
class ContainerInfo {
  ContainerInfo({
    required this.service,
    required this.name,
    required this.state,
    required this.status,
    this.image = '',
    this.ports = '',
  });
  final String service;
  final String name;
  final String state;
  final String status;
  final String image;
  final String ports;
  Map<String, Object?> toJson() => {
    'service': service,
    'name': name,
    'state': state,
    'status': status,
    'image': image,
    'ports': ports,
  };
}

extension ReleaseInfoJson on ReleaseInfo {
  Map<String, Object?> toJson({String? current}) => {
    'id': id,
    'status': status,
    'current': id == current,
    if (meta != null) ...meta!.toJson(),
  };
}

/// The state of one environment.
class EnvStatus {
  EnvStatus({
    required this.project,
    required this.env,
    required this.host,
    required this.dir,
    required this.current,
    required this.releases,
    required this.ports,
    required this.containers,
    required this.healthUrl,
    required this.healthy,
    this.diskFreeKb,
    this.diskTotalKb,
    this.releasesKb,
    this.logTables = const {},
    this.dns = const [],
    this.dnsNote,
  });

  factory EnvStatus.parse({
    required String project,
    required String env,
    required String host,
    required String dir,
    required EnvState state,
    required Map<String, int> ports,
    required String healthUrl,
    required String output,
  }) {
    final containers = <ContainerInfo>[];
    var healthy = false;
    int? free, total, rel;
    for (final line in const LineSplitter().convert(output)) {
      if (line.startsWith('PS ')) {
        final j = _decode(line.substring(3));
        containers.add(
          ContainerInfo(
            service: '${j['Service'] ?? ''}',
            name: '${j['Name'] ?? ''}',
            state: '${j['State'] ?? ''}',
            status: '${j['Status'] ?? ''}',
            image: '${j['Image'] ?? ''}',
            ports:
                '${j['Publishers'] is List ? [for (final x in j['Publishers'] as List)
                        if (x is Map && (x['PublishedPort'] ?? 0) != 0) '${x['URL']}:${x['PublishedPort']}->${x['TargetPort']}'].join(', ') : j['Ports'] ?? ''}',
          ),
        );
      } else if (line == 'HEALTH ok') {
        healthy = true;
      } else if (line.startsWith('DISK ')) {
        final p = line.split(' ');
        free = int.tryParse(p[1]);
        total = int.tryParse(p[2]);
      } else if (line.startsWith('RELEASES_KB ')) {
        rel = int.tryParse(line.substring(12));
      }
    }
    return EnvStatus(
      project: project,
      env: env,
      host: host,
      dir: dir,
      current: state.current,
      releases: state.releases.reversed.toList(),
      ports: ports,
      containers: containers,
      healthUrl: healthUrl,
      healthy: healthy,
      diskFreeKb: free,
      diskTotalKb: total,
      releasesKb: rel,
    );
  }

  final String project;
  final String env;
  final String host;
  final String dir;
  final String? current;

  /// Newest first.
  final List<ReleaseInfo> releases;
  final Map<String, int> ports;
  final List<ContainerInfo> containers;
  final String healthUrl;
  final bool healthy;
  final int? diskFreeKb;
  final int? diskTotalKb;
  final int? releasesKb;

  /// Serverpod's log tables: name → {rows, bytes}.
  final Map<String, Map<String, int>> logTables;

  /// Where each domain's DNS points, from the Cloudflare API (`state`:
  /// ok, missing, other_tunnel, elsewhere).
  final List<Map<String, Object?>> dns;

  /// Why [dns] is empty (no token, not Cloudflare, an API error).
  final String? dnsNote;

  /// Whether a domain points somewhere other than this environment.
  bool get dnsDrift => dns.any((d) => d['state'] != 'ok');

  EnvStatus withDns(List<Map<String, Object?>> d, {String? note}) => EnvStatus(
    project: project,
    env: env,
    host: host,
    dir: dir,
    current: current,
    releases: releases,
    ports: ports,
    containers: containers,
    healthUrl: healthUrl,
    healthy: healthy,
    diskFreeKb: diskFreeKb,
    diskTotalKb: diskTotalKb,
    releasesKb: releasesKb,
    logTables: logTables,
    dns: d,
    dnsNote: note,
  );

  EnvStatus withLogTables(Map<String, Map<String, int>> t) => EnvStatus(
    project: project,
    env: env,
    host: host,
    dir: dir,
    current: current,
    releases: releases,
    ports: ports,
    containers: containers,
    healthUrl: healthUrl,
    healthy: healthy,
    diskFreeKb: diskFreeKb,
    diskTotalKb: diskTotalKb,
    releasesKb: releasesKb,
    logTables: t,
    dns: dns,
    dnsNote: dnsNote,
  );

  Map<String, Object?> toJson() => {
    'log_tables': logTables,
    'dns': dns,
    'dns_note': ?dnsNote,
    'project': project,
    'env': env,
    'host': host,
    'dir': dir,
    'current': current,
    'releases': [for (final r in releases) r.toJson(current: current)],
    'ports': ports,
    'containers': [for (final c in containers) c.toJson()],
    'health_url': healthUrl,
    'healthy': healthy,
    'disk_free_kb': diskFreeKb,
    'disk_total_kb': diskTotalKb,
    'releases_kb': releasesKb,
  };
}

/// One backup on the server.
class BackupInfo {
  BackupInfo(this.stamp, this.size, this.encrypted);
  factory BackupInfo.parse(String line) {
    final p = line.trim().split(' ');
    return BackupInfo(p[0], p[1], p[2] == 'yes');
  }
  final String stamp;
  final String size;
  final bool encrypted;
  Map<String, Object?> toJson() => {
    'stamp': stamp,
    'size': size,
    'encrypted': encrypted,
  };
}

/// One variable of `.env`. Secret values are never read into this.
class EnvVarInfo {
  EnvVarInfo(this.name, {required this.secret, this.value});
  final String name;
  final bool secret;
  final String? value;
  Map<String, Object?> toJson() => {
    'name': name,
    'secret': secret,
    'value': ?value,
  };
}

/// A domain: its routes, its DNS answers and the proxy rules.
class DomainInfo {
  DomainInfo({
    required this.host,
    required this.routes,
    required this.dnsAnswers,
    required this.dnsNeeded,
    required this.proxyRules,
  });
  final String host;
  final List<String> routes;
  final List<String> dnsAnswers;
  final String dnsNeeded;
  final List<String> proxyRules;
  Map<String, Object?> toJson() => {
    'host': host,
    'routes': routes,
    'dns_answers': dnsAnswers,
    'dns_needed': dnsNeeded,
    'proxy_rules': proxyRules,
  };
}

/// Applied Serverpod migrations against the current release.
class MigrationStatus {
  MigrationStatus(this.applied, this.newestShipped, this.projectModule);

  factory MigrationStatus.parse(
    String appliedRows,
    String newest,
    String serverPackage,
  ) => MigrationStatus(
    [
      for (final l in const LineSplitter().convert(appliedRows))
        if (l.split(' | ').length >= 2)
          {
            'module': l.split(' | ')[0],
            'version': l.split(' | ')[1],
            if (l.split(' | ').length > 2) 'time': l.split(' | ')[2],
          },
    ],
    newest.isEmpty ? null : newest,
    serverPackage.replaceAll(RegExp(r'_server$'), ''),
  );

  final List<Map<String, String>> applied;
  final String? newestShipped;
  final String projectModule;

  String? get appliedVersion => [
    for (final a in applied)
      if (a['module'] == projectModule) a['version'],
  ].firstOrNull;

  /// up_to_date, pending, ahead or unknown.
  String get state {
    final a = appliedVersion, n = newestShipped;
    if (a == null || n == null) return 'unknown';
    if (a == n) return 'up_to_date';
    return a.compareTo(n) < 0 ? 'pending' : 'ahead';
  }

  Map<String, Object?> toJson() => {
    'applied': applied,
    'newest_in_release': newestShipped,
    'state': state,
  };
}

/// Every project and container on a server.
class ServerStatus {
  ServerStatus(
    this.host,
    this.registry,
    this.containers,
    this.diskFreeKb,
    this.diskTotalKb,
  );

  factory ServerStatus.parse(String host, Registry registry, String output) {
    final stats = <String, Map<String, Object?>>{};
    final containers = <Map<String, Object?>>[];
    int? free, total;
    for (final line in const LineSplitter().convert(output)) {
      if (line.startsWith('STAT ')) {
        final j = _decode(line.substring(5));
        stats['${j['Name']}'] = j;
      } else if (line.startsWith('PS ')) {
        containers.add(_decode(line.substring(3)));
      } else if (line.startsWith('DISK ')) {
        final p = line.split(' ');
        free = int.tryParse(p[1]);
        total = int.tryParse(p[2]);
      }
    }
    return ServerStatus(
      host,
      registry,
      [
        for (final c in containers)
          {
            'name': c['Names'],
            'project': RegExp(
              r'com\.docker\.compose\.project=([^,]+)',
            ).firstMatch('${c['Labels'] ?? ''}')?[1],
            'image': c['Image'],
            'status': c['Status'],
            'cpu': stats['${c['Names']}']?['CPUPerc'],
            'memory': stats['${c['Names']}']?['MemUsage'],
          },
      ],
      free,
      total,
    );
  }

  final String host;
  final Registry registry;
  final List<Map<String, Object?>> containers;
  final int? diskFreeKb;
  final int? diskTotalKb;

  Map<String, Object?> toJson() => {
    'host': host,
    'projects': [for (final e in registry.entries.values) e.toMap()],
    'containers': containers,
    'disk_free_kb': diskFreeKb,
    'disk_total_kb': diskTotalKb,
  };
}
