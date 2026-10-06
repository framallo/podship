// Turns an environment's config plus the server registry into concrete
// values: ports, health URL, domain routes and the registry entry.

import '../config/config.dart';
import '../server/registry.dart';

/// A domain route with a concrete port.
class ResolvedRoute {
  ResolvedRoute(this.path, this.port);
  final String? path;
  final int port;
}

class ResolvedEnv {
  ResolvedEnv({
    required this.env,
    required this.ports,
    required this.domains,
    required this.entry,
    required this.backupSchedule,
  });

  final EnvConfig env;
  final Map<String, int> ports;
  final Map<String, List<ResolvedRoute>> domains;
  final RegistryEntry entry;

  /// The backup `OnCalendar`, from the config or a free registry slot.
  final String? backupSchedule;

  /// Replaces `{port:name}` in [s].
  String sub(String s) =>
      s.replaceAllMapped(RegExp(r'\{port:([A-Za-z0-9_-]+)\}'), (m) {
        final p = ports[m[1]];
        if (p == null) throw ConfigException('unknown port "${m[1]}" in "$s"');
        return '$p';
      });

  String get healthUrl => sub(env.health.url);
  String? get publicHealthUrl =>
      env.health.publicUrl == null ? null : sub(env.health.publicUrl!);

  /// Serverpod's readiness probe, when the deploy is gated on it.
  String? get readinessUrl {
    final sp = env.serverpod;
    if (!sp.readiness) return null;
    if (sp.readinessUrl != null) return sub(sp.readinessUrl!);
    final port = ports['web'] ?? ports['api'];
    return port == null ? null : 'http://127.0.0.1:$port/readyz';
  }

  /// Every URL that counts as healthy on the server, primary first.
  List<String> get healthUrls => [
    healthUrl,
    ...env.health.fallbackUrls.map(sub),
  ];

  /// Every public URL that counts as healthy, primary first.
  List<String> get publicHealthUrls => [
    ?publicHealthUrl,
    if (publicHealthUrl != null) ...env.health.publicFallbackUrls.map(sub),
  ];
}

/// Resolves [env] of [config] against [registry]. [listening] are ports in
/// use on the server. [now] stamps the registry entry.
ResolvedEnv resolveEnv(
  PodshipConfig config,
  EnvConfig env,
  Registry registry, {
  Set<int> listening = const {},
  String now = '',
}) {
  final key = '${config.project}/${env.name}';
  // A port this environment already holds is not "in use by someone else".
  final mine = registry.entries[key]?.ports.values.toSet() ?? const {};
  final ports = registry.allocatePorts(
    key,
    env.ports,
    listening: listening.difference(mine),
  );
  int portOf(String ref) {
    final n = int.tryParse(ref);
    if (n != null) return n;
    final p = ports[ref];
    if (p == null) {
      throw ConfigException(
        'environments.${env.name}: route port "$ref" is not in ports:',
      );
    }
    return p;
  }

  final domains = {
    for (final d in env.domains)
      d.host: [for (final r in d.routes) ResolvedRoute(r.path, portOf(r.port))],
  };
  final backup = env.backup;
  String? schedule;
  if (backup != null) {
    schedule = backup.schedule.isNotEmpty
        ? backup.schedule
        : registry.allocateBackupSchedule(key, timezone: backup.timezone);
  }
  final entry = RegistryEntry(
    project: config.project,
    env: env.name,
    dir: env.dir,
    composeProject: env.composeProject,
    ports: {
      ...ports,
      // Routed ports given as numbers count too.
      for (final d in domains.entries)
        for (final (i, r) in d.value.indexed)
          if (!ports.containsValue(r.port)) '${d.key}#$i': r.port,
    },
    domains: [for (final d in env.domains) d.host],
    database: env.database.mode == DatabaseMode.shared
        ? 'shared:${env.database.name}'
        : 'per_env:${env.composeProject}/${env.database.name}',
    backupUnit: backup?.unit,
    backupSchedule: schedule,
    updated: now,
  );
  registry.check(entry);
  return ResolvedEnv(
    env: env,
    ports: ports,
    domains: domains,
    entry: entry,
    backupSchedule: schedule,
  );
}
