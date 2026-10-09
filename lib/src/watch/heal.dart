// Pure rules of the watch: whose alert it is (the owner's heartbeat) and
// which services a heal restarts. No IO.

import 'dart:convert';

/// Why the owner's heartbeat [hb] counts as dead at [now], or null when the
/// owner's watch is alive (then the owner alerts, not the cross-watch).
/// Dead: out of reach (null), unreadable, or older than three intervals
/// (at least 5 min), unless the owner says it is busy healing.
String? heartbeatStale(
  Map<String, Object?>? hb,
  DateTime now, {
  required int interval,
}) {
  if (hb == null) return 'is out of reach (no heartbeat)';
  final t = DateTime.tryParse('${hb['time']}');
  if (t == null) return 'has an unreadable heartbeat';
  final busy = DateTime.tryParse('${hb['busy_until'] ?? ''}');
  if (busy != null && now.isBefore(busy)) return null;
  final every = (hb['interval'] as num?)?.toInt() ?? interval;
  var limit = Duration(seconds: every * 3);
  if (limit < const Duration(minutes: 5)) limit = const Duration(minutes: 5);
  final age = now.difference(t);
  return age > limit ? 'has a stale heartbeat (${age.inSeconds} s old)' : null;
}

/// One container of `docker compose ps -a --format json`.
class ComposeService {
  ComposeService({
    required this.service,
    required this.state,
    this.health = '',
    this.image = '',
  });
  final String service;

  /// `running`, `exited`, `restarting`, `created`, …
  final String state;

  /// `healthy`, `unhealthy`, `starting`, or empty (no health check).
  final String health;
  final String image;

  bool get failing => state != 'running' || health == 'unhealthy';

  /// Postgres (or another database) of the environment.
  bool get isDatabase =>
      image.contains('postgres') ||
      const {
        'postgres',
        'db',
        'database',
        'mysql',
        'mariadb',
      }.contains(service);
}

/// Parses `compose ps --format json`: one JSON object per line (Compose
/// 2.21 and later) or one JSON array (older).
List<ComposeService> parseComposePs(String out) {
  final rows = <Map>[];
  final text = out.trim();
  if (text.startsWith('[')) {
    try {
      rows.addAll((jsonDecode(text) as List).whereType<Map>());
    } catch (_) {}
  } else {
    for (final l in const LineSplitter().convert(text)) {
      if (!l.trim().startsWith('{')) continue;
      try {
        rows.add(jsonDecode(l) as Map);
      } catch (_) {}
    }
  }
  return [
    for (final r in rows)
      ComposeService(
        service: '${r['Service'] ?? ''}',
        state: '${r['State'] ?? ''}',
        health: '${r['Health'] ?? ''}',
        image: '${r['Image'] ?? ''}',
      ),
  ];
}

/// The app services: the environment's server service, `server`, `api`
/// and `web`.
Set<String> appServices(String serverService) => {
  serverService,
  'server',
  'api',
  'web',
};

/// The services a heal restarts: the failing ones (stopped or unhealthy),
/// the database only when the database itself fails. When nothing looks
/// failing (the containers run, but the app does not answer), the app
/// services. When `compose ps` gave nothing, the server service.
List<String> servicesToHeal(
  List<ComposeService>? ps, {
  String serverService = 'server',
}) {
  if (ps == null || ps.isEmpty) return [serverService];
  final apps = appServices(serverService);
  final failing = <String>{
    for (final s in ps)
      if (s.failing) s.service,
  };
  if (failing.isNotEmpty) return failing.toList()..sort();
  final present = <String>{
    for (final s in ps)
      if (apps.contains(s.service) && !s.isDatabase) s.service,
  };
  return (present.isEmpty ? [serverService] : present.toList())..sort();
}
