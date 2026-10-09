// What `podship watch` watches on a machine: the `watch:` section of the
// machine's registry (`<podship_home>/registry.yaml`).
//
// `podship watch install --env <env>` writes a target per environment: on
// the environment's own server a target that may heal, and on every other
// machine of the fleet a copy that only alerts (the cross-watch). The
// scheduler agent reads the section at every tick.

import 'dart:convert';

/// One public check (`health.public_checks`, or the `public_url`).
class WatchCheck {
  WatchCheck({
    required this.url,
    this.method = 'GET',
    this.status = const [],
    this.contentType,
    this.contains,
  });

  factory WatchCheck.fromMap(Map m) => WatchCheck(
    url: '${m['url']}',
    method: '${m['method'] ?? 'GET'}'.toUpperCase(),
    status: [for (final s in (m['status'] as List?) ?? const []) s as int],
    contentType: m['content_type'] as String?,
    contains: m['contains'] as String?,
  );

  final String url;
  final String method;

  /// Accepted status codes; empty: any 2xx.
  final List<int> status;
  final String? contentType;
  final String? contains;

  Map<String, Object?> toMap() => {
    'url': url,
    if (method != 'GET') 'method': method,
    if (status.isNotEmpty) 'status': status,
    'content_type': ?contentType,
    'contains': ?contains,
  };
}

/// One environment that a machine watches.
class WatchTarget {
  WatchTarget({
    required this.project,
    required this.env,
    required this.checks,
    this.owner = true,
    this.machine,
    this.heal = true,
    this.localUrls = const [],
    this.releaseDir,
    this.path,
    this.updated = '',
  });

  factory WatchTarget.fromMap(Map m) => WatchTarget(
    project: '${m['project']}',
    env: '${m['env']}',
    checks: [
      for (final c in (m['checks'] as List?) ?? const [])
        WatchCheck.fromMap(c as Map),
    ],
    owner: m['owner'] as bool? ?? true,
    machine: m['machine'] as String?,
    heal: m['heal'] as bool? ?? true,
    localUrls: [for (final u in (m['local_urls'] as List?) ?? const []) '$u'],
    releaseDir: m['release_dir'] as String?,
    path: m['path'] as String?,
    updated: '${m['updated'] ?? ''}',
  );

  final String project;
  final String env;
  final List<WatchCheck> checks;

  /// The environment runs on this machine: the watch may heal it.
  final bool owner;

  /// The machine the environment runs on (for a cross-watch copy).
  final String? machine;

  /// Heal on failure (owner only): start the Docker engine, then
  /// `podship restart`.
  final bool heal;

  /// Health URLs on this machine (loopback), to tell a dead app from a dead
  /// tunnel. Owner only.
  final List<String> localUrls;

  /// `<dir>/current`: the release whose `podship.yaml` the restart reads.
  final String? releaseDir;

  /// Extra PATH entries (the environment's `remote_path`): docker, colima.
  final String? path;
  final String updated;

  String get key => '$project/$env';

  /// Heals only on its own machine.
  bool get heals => owner && heal && releaseDir != null;

  Map<String, Object?> toMap() => {
    'project': project,
    'env': env,
    'owner': owner,
    'machine': ?machine,
    'heal': heal,
    'checks': [for (final c in checks) c.toMap()],
    if (localUrls.isNotEmpty) 'local_urls': localUrls,
    'release_dir': ?releaseDir,
    'path': ?path,
    'updated': updated,
  };
}

/// The Docker engine of a machine, which the watch starts when it does not
/// answer.
enum Engine {
  /// Detect: Colima when `colima` is on the PATH, else Docker Desktop when
  /// `/Applications/Docker.app` exists.
  auto,
  dockerDesktop,
  colima,

  /// Never start an engine (Linux servers: systemd restarts dockerd).
  none;

  String get id => switch (this) {
    auto => 'auto',
    dockerDesktop => 'docker_desktop',
    colima => 'colima',
    none => 'none',
  };

  static Engine parse(String? s) => switch (s) {
    'docker_desktop' || 'docker-desktop' => dockerDesktop,
    'colima' => colima,
    'none' => none,
    _ => auto,
  };
}

/// The `watch:` section of a machine's registry.
class WatchSettings {
  WatchSettings({
    this.interval = defaultInterval,
    this.alertAfter = 2,
    this.healAttempts = 2,
    this.healBackoff = 360,
    this.engine = Engine.auto,
    Map<String, Map<String, Object?>>? channels,
    Map<String, WatchTarget>? targets,
    this.machine,
  }) : channels = channels ?? {},
       targets = targets ?? {};

  factory WatchSettings.fromMap(Map? m) {
    if (m == null) return WatchSettings();
    final ch = <String, Map<String, Object?>>{};
    for (final e in ((m['channels'] as Map?) ?? const {}).entries) {
      ch['${e.key}'] =
          jsonDecode(jsonEncode(e.value ?? {})) as Map<String, Object?>;
    }
    final ts = <String, WatchTarget>{};
    for (final e in ((m['targets'] as Map?) ?? const {}).entries) {
      final t = WatchTarget.fromMap(e.value as Map);
      ts[t.key] = t;
    }
    return WatchSettings(
      interval: (m['interval'] as num?)?.toInt() ?? defaultInterval,
      alertAfter: (m['alert_after'] as num?)?.toInt() ?? 2,
      healAttempts: (m['heal_attempts'] as num?)?.toInt() ?? 2,
      healBackoff: (m['heal_backoff'] as num?)?.toInt() ?? 360,
      engine: Engine.parse(m['engine'] as String?),
      channels: ch,
      targets: ts,
      machine: m['machine'] as String?,
    );
  }

  static const defaultInterval = 120;

  /// Seconds between two watch runs (the agent's `StartInterval`).
  int interval;

  /// Failed runs in a row that open an incident and send the alert.
  int alertAfter;

  /// Heal attempts per incident.
  int healAttempts;

  /// Seconds between two heal attempts of one incident.
  int healBackoff;
  Engine engine;

  /// The alert channels (`notify.channels` syntax): `macos`, `email` with
  /// `to`, `from` and `region`, `webhook`, `slack`. Empty: a macOS
  /// notification.
  final Map<String, Map<String, Object?>> channels;
  final Map<String, WatchTarget> targets;

  /// The name of this machine in alerts.
  String? machine;

  bool get isEmpty => targets.isEmpty && channels.isEmpty && machine == null;

  /// Everything but the targets, for the three-way merge.
  Map<String, Object?> settingsMap() => {
    'machine': ?machine,
    'interval': interval,
    'alert_after': alertAfter,
    'heal_attempts': healAttempts,
    'heal_backoff': healBackoff,
    'engine': engine.id,
    'channels': channels,
  };

  Map<String, Object?> toMap() => {
    ...settingsMap(),
    'targets': {for (final t in targets.values) t.key: t.toMap()},
  };

  WatchSettings copy() =>
      WatchSettings.fromMap(jsonDecode(jsonEncode(toMap())) as Map);
}
