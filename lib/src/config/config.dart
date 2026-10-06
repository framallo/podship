// The model of `podship.yaml`, and its parser.
//
// The file lives in the project root and is committed. It holds no secrets:
// secrets live only on the servers.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The name of the config file in the project root.
const configFileName = 'podship.yaml';

/// A problem in `podship.yaml`.
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'podship.yaml: $message';
}

/// A Flutter web app that is built locally and shipped with the server.
class FlutterWebApp {
  FlutterWebApp({
    required this.name,
    required this.path,
    required this.output,
    required this.baseHref,
    this.args = const [],
  });

  /// A short name for messages.
  final String name;

  /// The Flutter package, relative to the project root.
  final String path;

  /// Where the build goes, relative to the project root. Usually a folder
  /// under the server's `web/` directory.
  final String output;

  /// The `--base-href` of the build, like `/app/`.
  final String baseHref;

  /// Extra arguments for `flutter build web`.
  final List<String> args;
}

/// Build settings shared by all environments.
class BuildConfig {
  BuildConfig({
    this.source = SourceMode.git,
    this.ref = 'HEAD',
    this.flutterWeb = const [],
    this.preDeploy = const [],
    this.postDeploy = const [],
    this.files = const [],
  });

  /// Where the release files come from.
  final SourceMode source;

  /// The git ref to deploy when [source] is [SourceMode.git].
  final String ref;
  final List<FlutterWebApp> flutterWeb;

  /// Local shell commands. They run in the snapshot before the upload.
  final List<String> preDeploy;

  /// Local shell commands. They run in the project root after a healthy
  /// deploy.
  final List<String> postDeploy;

  /// File rules in gitignore syntax, applied after `.gitignore` and
  /// `.podshipignore`. `!pattern` includes files again.
  final List<String> files;
}

/// Where the files of a release come from.
enum SourceMode {
  /// A clean export of a git commit (`git archive`). Uncommitted changes are
  /// not shipped.
  git,

  /// The working tree as it is, uncommitted changes included.
  worktree,
}

/// Compose settings shared by all environments.
class ComposeConfig {
  ComposeConfig({
    this.files = const ['docker-compose.yml'],
    this.buildContexts = const {},
    this.remotePreBuild = const [],
  });

  /// Compose files, relative to the project root. They are shipped.
  final List<String> files;

  /// Build contexts that live on the server and are not shipped, keyed by
  /// service, like `pacewright: /srv/pacewright`.
  final Map<String, String> buildContexts;

  /// Shell commands that run on the server before the build.
  final List<String> remotePreBuild;
}

/// How scheduled jobs run on a server.
enum Scheduler {
  /// systemd on Linux, launchd on macOS (detected on the server).
  auto,
  systemd,
  launchd,
}

/// How migrations are applied.
enum MigrationMode {
  /// The server applies them when it starts (`--apply-migrations` in the
  /// compose file). podship does nothing.
  onStart,

  /// podship runs the server once with `--role=maintenance
  /// --apply-migrations` before it switches traffic.
  maintenance,

  /// Migrations are not applied.
  none,
}

/// The health check that gates a deploy.
class HealthConfig {
  HealthConfig({
    required this.url,
    this.publicUrl,
    this.attempts = 20,
    this.intervalSeconds = 6,
  });

  /// A URL that is fetched ON THE SERVER, usually a loopback port.
  final String url;

  /// An optional public URL that is fetched from this machine.
  final String? publicUrl;
  final int attempts;
  final int intervalSeconds;
}

/// Where the secrets of an environment live on the server.
class SecretsConfig {
  SecretsConfig({
    this.envFile = 'shared/.env',
    this.passwordsFile = 'shared/passwords.yaml',
    this.passwordsLink,
    this.template,
    this.generate = const [],
    this.databasePasswordEnv,
    this.passwordKeys = const [],
  });

  /// The `.env` file, relative to the environment directory.
  final String envFile;

  /// The Serverpod `passwords.yaml`, relative to the environment directory.
  final String passwordsFile;

  /// Where each release sees `passwords.yaml`, relative to the release.
  /// Defaults to `<server_package>/config/passwords.yaml`.
  final String? passwordsLink;

  /// A local `.env` template (no values), used by `secret init`.
  final String? template;

  /// `.env` variables that `secret init` fills with random values.
  final List<String> generate;

  /// The `.env` variable that must hold the same value as the `database`
  /// password, for the Postgres container.
  final String? databasePasswordEnv;

  /// `passwords.yaml` keys that `secret init` generates. Empty means the
  /// keys of the local `config/passwords.yaml` plus `database` and
  /// `serviceSecret`.
  final List<String> passwordKeys;
}

/// One route of a domain: a path regex and a loopback port.
class DomainRoute {
  DomainRoute({this.path, required this.port});
  final String? path;

  /// A port number, or the name of a port in `ports:`.
  final String port;
}

class DomainConfig {
  DomainConfig({required this.host, required this.routes});
  final String host;
  final List<DomainRoute> routes;
}

/// The reverse proxy in front of an environment.
enum ProxyKind { cloudflareTunnel, caddy, none }

class ProxyConfig {
  ProxyConfig({
    this.kind = ProxyKind.none,
    this.config,
    this.service,
    this.tunnelId,
  });
  final ProxyKind kind;

  /// The proxy's config file on the server. For Caddy, the site file that
  /// podship owns.
  final String? config;

  /// The systemd unit to restart or reload.
  final String? service;

  /// The Cloudflare tunnel id, for the DNS record podship prints.
  final String? tunnelId;
}

/// A Docker volume that the backup archives.
class BackupVolume {
  BackupVolume({
    required this.name,
    required this.volume,
    this.sqlite = const [],
    this.files = const [],
  });

  /// The archive name, like `pacewright` → `pacewright.tar.zst`.
  final String name;

  /// The Docker volume name.
  final String volume;

  /// SQLite files that are copied with SQLite's backup API.
  final List<String> sqlite;

  /// Other files to copy. Empty means the whole volume.
  final List<String> files;
}

/// File and folder names inside the backup directory.
class BackupLayout {
  BackupLayout({
    this.plain = 'plain',
    this.encrypted = 'encrypted',
    this.dump = 'db.dump',
    this.counts = 'counts.txt',
    this.secrets = 'secrets',
  });
  final String plain;
  final String encrypted;
  final String dump;
  final String counts;
  final String secrets;
}

class BackupConfig {
  BackupConfig({
    required this.dir,
    required this.unit,
    this.beforeDeploy = true,
    this.schedule = '',
    this.timezone = 'UTC',
    this.keepDays = 14,
    this.keepWeeks = 8,
    this.keepMonths = 6,
    this.recipients = const [],
    this.ageRecipientsRemote,
    this.volumes = const [],
    BackupLayout? layout,
    this.stopOnRestore = const [],
    this.drillTables = const [],
    this.drillVolatile = const [],
    this.offsiteDir,
    this.offsiteIdentities = const ['~/.ssh/id_ed25519'],
    this.compression = 'zstd',
  }) : layout = layout ?? BackupLayout();

  /// The backup directory on the server.
  final String dir;

  /// The systemd unit name (service and timer).
  final String unit;
  final bool beforeDeploy;

  /// A systemd `OnCalendar` value. Empty means "a free slot from the
  /// server registry" (03:00, 03:15, 03:30 …).
  final String schedule;
  final String timezone;
  final int keepDays;
  final int keepWeeks;
  final int keepMonths;

  /// Who can decrypt the off-site copies. Each entry is a public key (an
  /// SSH key like `ssh-ed25519 AAAA…`, or an age key `age1…`), or a local
  /// file of such keys (like `~/.ssh/id_ed25519.pub`). podship writes them
  /// to one recipients file on the server. Decrypt with the matching SSH
  /// private key: `age -d -i ~/.ssh/id_ed25519`.
  final List<String> recipients;

  /// Where the age public key lives on the server.
  final String? ageRecipientsRemote;
  final List<BackupVolume> volumes;
  final BackupLayout layout;

  /// Services to stop while a database restore runs. Empty means every
  /// service except the database.
  final List<String> stopOnRestore;

  /// Tables the drill compares (glob). Empty means all tables.
  final List<String> drillTables;

  /// Tables that may change between the dump and the count (glob).
  final List<String> drillVolatile;

  /// The local folder that `backup pull` copies encrypted backups to.
  final String? offsiteDir;

  /// Local private keys that `backup pull` tries, in order, to check the
  /// newest copy: SSH keys (like `~/.ssh/id_ed25519`) or age identity files.
  /// Keep an old key here to read archives made before a key change.
  final List<String> offsiteIdentities;

  /// `zstd` or `gzip`, for volume archives.
  final String compression;
}

/// Where the database of an environment runs.
enum DatabaseMode {
  /// A Postgres service in the environment's own compose project (default).
  perEnv,

  /// One Postgres container for the whole server (`podship-postgres`).
  /// Each environment gets its own database and role in it.
  shared,
}

class DatabaseConfig {
  DatabaseConfig({
    this.mode = DatabaseMode.perEnv,
    this.service = 'postgres',
    this.name = 'serverpod',
    this.user = 'postgres',
  });
  final DatabaseMode mode;

  /// The compose service of the database (per-env mode).
  final String service;
  final String name;
  final String user;

  /// The container that runs the shared Postgres.
  static const sharedContainer = 'podship-postgres';

  /// The Docker network that reaches the shared Postgres.
  static const sharedNetwork = 'podship-shared';
}

/// One environment, like `production` or `staging`.
class EnvConfig {
  EnvConfig({
    required this.name,
    required this.host,
    required this.dir,
    required this.composeProject,
    this.composeFiles = const [],
    this.runMode = 'production',
    this.ports = const {},
    required this.health,
    SecretsConfig? secrets,
    this.plainEnv = const [],
    this.migrations = MigrationMode.onStart,
    this.keepReleases = 5,
    DatabaseConfig? database,
    this.backup,
    ProxyConfig? proxy,
    this.domains = const [],
    this.remotePath,
    this.serverService = 'server',
    this.podshipHome = '/srv/podship',
    this.buildContexts,
    this.remotePreBuild,
    this.scheduler = Scheduler.auto,
  }) : secrets = secrets ?? SecretsConfig(),
       database = database ?? DatabaseConfig(),
       proxy = proxy ?? ProxyConfig();

  final String name;

  /// The ssh destination. `~/.ssh/config` aliases work.
  final String host;

  /// The environment directory on the server.
  final String dir;
  final String composeProject;

  /// Extra compose files for this environment, appended to the shared ones.
  final List<String> composeFiles;
  final String runMode;

  /// Loopback ports this environment publishes, by name. 0 means "auto":
  /// the server registry allocates a free port.
  final Map<String, int> ports;
  final HealthConfig health;
  final SecretsConfig secrets;

  /// Variables in `.env` that are not secret. Their values may be printed.
  final List<String> plainEnv;
  final MigrationMode migrations;
  final int keepReleases;
  final DatabaseConfig database;
  final BackupConfig? backup;
  final ProxyConfig proxy;
  final List<DomainConfig> domains;

  /// A directory prepended to PATH on the server.
  final String? remotePath;

  /// The compose service that runs the Serverpod server.
  final String serverService;

  /// podship's own folder on the server: the registry, the backup scripts
  /// and their settings. One per server, shared by all projects.
  final String podshipHome;

  /// Overrides `compose.build_contexts` for this environment.
  final Map<String, String>? buildContexts;

  /// Overrides `compose.remote_pre_build` for this environment.
  final List<String>? remotePreBuild;

  /// How scheduled backups run on the server.
  final Scheduler scheduler;

  bool get isProduction => name == 'production';
  String get registryPath => '$podshipHome/registry.yaml';
  String get libDir => '$podshipHome/lib';
  String get etcDir => '$podshipHome/etc';
}

/// The whole `podship.yaml`.
class PodshipConfig {
  PodshipConfig({
    required this.project,
    required this.serverPackage,
    required this.build,
    required this.compose,
    required this.environments,
    this.root = '.',
  });

  /// The project name. Destructive commands ask you to type it.
  final String project;

  /// The Serverpod server package, relative to the project root.
  final String serverPackage;
  final BuildConfig build;
  final ComposeConfig compose;
  final Map<String, EnvConfig> environments;

  /// The project root (the folder of `podship.yaml`).
  final String root;

  EnvConfig env(String name) {
    final e = environments[name];
    if (e == null) {
      throw ConfigException(
        'no environment "$name". Known: ${environments.keys.join(', ')}',
      );
    }
    return e;
  }

  /// Reads `podship.yaml` from [dir] or its parents.
  static PodshipConfig load([String? dir]) {
    var d = Directory(dir ?? Directory.current.path).absolute;
    while (true) {
      final f = File(p.join(d.path, configFileName));
      if (f.existsSync()) {
        return parse(f.readAsStringSync(), root: d.path);
      }
      final parent = d.parent;
      if (parent.path == d.path) {
        throw ConfigException(
          'not found in ${dir ?? Directory.current.path} or its parents. '
          'Run `podship init`.',
        );
      }
      d = parent;
    }
  }

  /// Parses the YAML text of `podship.yaml`.
  static PodshipConfig parse(String text, {String root = '.'}) {
    final doc = loadYaml(text);
    if (doc is! YamlMap) throw ConfigException('the top level must be a map');
    final r = _Reader(doc, '');
    final project = r.str('project');
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(project)) {
      throw ConfigException(
        'project must be lowercase letters, digits, - and _',
      );
    }
    final serverPackage = r.str('server_package', '${project}_server');

    final b = r.map('build');
    final build = BuildConfig(
      source: switch (b.str('source', 'git')) {
        'git' => SourceMode.git,
        'worktree' => SourceMode.worktree,
        final s => throw ConfigException('build.source: unknown "$s"'),
      },
      ref: b.str('ref', 'HEAD'),
      flutterWeb: [
        for (final (i, m) in b.maps('flutter_web').indexed)
          FlutterWebApp(
            name: m.str('name', 'web$i'),
            path: m.str('path'),
            output: m.str('output'),
            baseHref: m.str('base_href', '/'),
            args: m.strs('args'),
          ),
      ],
      preDeploy: b.strs('pre_deploy'),
      postDeploy: b.strs('post_deploy'),
      files: b.strs('files'),
    );

    final c = r.map('compose');
    final compose = ComposeConfig(
      files: c.strs('files', const ['docker-compose.yml']),
      buildContexts: c.strMap('build_contexts'),
      remotePreBuild: c.strs('remote_pre_build'),
    );

    final envs = <String, EnvConfig>{};
    final em = r.map('environments');
    if (em.keys.isEmpty) {
      throw ConfigException('environments: define at least one');
    }
    for (final name in em.keys) {
      envs[name] = _parseEnv(name, em.map(name), project, serverPackage);
    }
    _checkIsolation(envs.values.toList());

    return PodshipConfig(
      project: project,
      serverPackage: serverPackage,
      build: build,
      compose: compose,
      environments: envs,
      root: root,
    );
  }

  static EnvConfig _parseEnv(
    String name,
    _Reader e,
    String project,
    String serverPackage,
  ) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(name)) {
      throw ConfigException('environment name "$name" is not valid');
    }
    final h = e.map('health');
    final s = e.map('secrets');
    final d = e.map('database');
    final px = e.map('proxy');
    final composeProject = e.str(
      'compose_project',
      name == 'production' ? project : '$project-$name',
    );
    final dir = e.str('dir');
    if (!dir.startsWith('/')) {
      throw ConfigException('environments.$name.dir must be absolute');
    }
    BackupConfig? backup;
    if (e.has('backup')) {
      final bk = e.map('backup');
      final l = bk.map('layout');
      final ret = bk.map('retention');
      final drill = bk.map('drill');
      final off = bk.map('offsite');
      backup = BackupConfig(
        dir: bk.str('dir', '/srv/backups/$composeProject'),
        unit: bk.str('unit', 'podship-backup-$composeProject'),
        beforeDeploy: bk.boolean('before_deploy', true),
        schedule: bk.str('schedule', ''),
        timezone: bk.str('timezone', 'UTC'),
        keepDays: ret.integer('days', 14),
        keepWeeks: ret.integer('weeks', 8),
        keepMonths: ret.integer('months', 6),
        recipients: bk.strs('recipients'),
        ageRecipientsRemote: bk.optStr('age_recipients_remote'),
        volumes: [
          for (final v in bk.maps('volumes'))
            BackupVolume(
              name: v.str('name'),
              volume: v.str('volume', '${composeProject}_${v.str('name')}'),
              sqlite: v.strs('sqlite'),
              files: v.strs('files'),
            ),
        ],
        layout: BackupLayout(
          plain: l.str('plain', 'plain'),
          encrypted: l.str('encrypted', 'encrypted'),
          dump: l.str('dump', 'db.dump'),
          counts: l.str('counts', 'counts.txt'),
          secrets: l.str('secrets', 'secrets'),
        ),
        stopOnRestore: bk.strs('stop_on_restore'),
        drillTables: drill.strs('tables'),
        drillVolatile: drill.strs('volatile'),
        offsiteDir: off.optStr('dir'),
        offsiteIdentities: off.strs('identities', const ['~/.ssh/id_ed25519']),
        compression: bk.str('compression', 'zstd'),
      );
      if (!const ['zstd', 'gzip'].contains(backup.compression)) {
        throw ConfigException(
          'environments.$name.backup.compression must be zstd or gzip',
        );
      }
    }
    return EnvConfig(
      name: name,
      host: e.str('host'),
      dir: dir,
      composeProject: composeProject,
      composeFiles: e.strs('compose_files'),
      runMode: e.str('run_mode', 'production'),
      ports: e.portMap('ports'),
      health: HealthConfig(
        url: h.str('url'),
        publicUrl: h.optStr('public_url'),
        attempts: h.integer('attempts', 20),
        intervalSeconds: h.integer('interval', 6),
      ),
      secrets: SecretsConfig(
        envFile: s.str('env_file', 'shared/.env'),
        passwordsFile: s.str('passwords_file', 'shared/passwords.yaml'),
        passwordsLink: s.str(
          'passwords_link',
          '$serverPackage/config/passwords.yaml',
        ),
        template: s.optStr('template'),
        generate: s.strs('generate'),
        databasePasswordEnv: s.optStr('database_password_env'),
        passwordKeys: s.strs('password_keys'),
      ),
      plainEnv: e.strs('plain_env'),
      migrations: switch (e.str('migrations', 'on_start')) {
        'on_start' => MigrationMode.onStart,
        'maintenance' => MigrationMode.maintenance,
        'none' => MigrationMode.none,
        final m => throw ConfigException(
          'environments.$name.migrations: unknown "$m"',
        ),
      },
      keepReleases: e.map('releases').integer('keep', 5),
      database: DatabaseConfig(
        mode: switch (d.str('mode', 'per_env')) {
          'per_env' => DatabaseMode.perEnv,
          'shared' => DatabaseMode.shared,
          final m => throw ConfigException(
            'environments.$name.database.mode: unknown "$m"',
          ),
        },
        service: d.str('service', 'postgres'),
        name: d.str(
          'name',
          d.str('mode', 'per_env') == 'shared'
              ? composeProject.replaceAll('-', '_')
              : project,
        ),
        user: d.str(
          'user',
          d.str('mode', 'per_env') == 'shared'
              ? composeProject.replaceAll('-', '_')
              : 'postgres',
        ),
      ),
      backup: backup,
      proxy: ProxyConfig(
        kind: switch (px.str('kind', 'none')) {
          'cloudflare_tunnel' => ProxyKind.cloudflareTunnel,
          'caddy' => ProxyKind.caddy,
          'none' => ProxyKind.none,
          final k => throw ConfigException(
            'environments.$name.proxy.kind: unknown "$k"',
          ),
        },
        config: px.optStr('config'),
        service: px.optStr('service'),
        tunnelId: px.optStr('tunnel_id'),
      ),
      domains: [
        for (final dm in e.maps('domains'))
          DomainConfig(
            host: dm.str('host'),
            routes: [
              for (final rt in dm.maps('routes'))
                DomainRoute(path: rt.optStr('path'), port: rt.str('port')),
            ],
          ),
      ],
      remotePath: e.optStr('remote_path'),
      serverService: e.str('server_service', 'server'),
      podshipHome: e.str('podship_home', '/srv/podship'),
      buildContexts: e.has('build_contexts')
          ? e.strMap('build_contexts')
          : null,
      remotePreBuild: e.has('remote_pre_build')
          ? e.strs('remote_pre_build')
          : null,
      scheduler: switch (e.str('scheduler', 'auto')) {
        'auto' => Scheduler.auto,
        'systemd' => Scheduler.systemd,
        'launchd' => Scheduler.launchd,
        final x => throw ConfigException(
          'environments.$name.scheduler: unknown "$x"',
        ),
      },
    );
  }

  /// Environments on the same host must not share a directory, a compose
  /// project, a port, a domain or a backup directory.
  static void _checkIsolation(List<EnvConfig> envs) {
    for (var i = 0; i < envs.length; i++) {
      for (var j = i + 1; j < envs.length; j++) {
        final a = envs[i], b = envs[j];
        if (a.host != b.host) continue;
        void clash(String what) => throw ConfigException(
          'environments ${a.name} and ${b.name} share $what on ${a.host}',
        );
        if (a.dir == b.dir) clash('the directory ${a.dir}');
        if (a.composeProject == b.composeProject) {
          clash('the compose project ${a.composeProject}');
        }
        final ports = a.ports.values
            .where((x) => x > 0)
            .toSet()
            .intersection(b.ports.values.where((x) => x > 0).toSet());
        if (ports.isNotEmpty) clash('port ${ports.first}');
        if (a.backup != null &&
            b.backup != null &&
            (a.backup!.dir == b.backup!.dir ||
                a.backup!.unit == b.backup!.unit)) {
          clash('a backup directory or unit');
        }
      }
    }
    final hosts = <String, String>{};
    for (final e in envs) {
      for (final d in e.domains) {
        final other = hosts[d.host];
        if (other != null) {
          throw ConfigException(
            'environments $other and ${e.name} share the domain ${d.host}',
          );
        }
        hosts[d.host] = e.name;
      }
    }
  }
}

/// Typed access to a YAML map, with paths in error messages.
class _Reader {
  _Reader(this._m, this._path);
  final YamlMap? _m;
  final String _path;

  String _k(String key) => _path.isEmpty ? key : '$_path.$key';
  Iterable<String> get keys => _m?.keys.cast<String>() ?? const [];
  bool has(String key) => _m?.containsKey(key) ?? false;

  Object? _get(String key) => _m?[key];

  String str(String key, [String? def]) {
    final v = _get(key);
    if (v == null) {
      if (def != null) return def;
      throw ConfigException('${_k(key)} is required');
    }
    if (v is String || v is num || v is bool) return '$v';
    throw ConfigException('${_k(key)} must be a string');
  }

  String? optStr(String key) => _get(key) == null ? null : str(key);

  int integer(String key, [int? def]) {
    final v = _get(key);
    if (v == null) {
      if (def != null) return def;
      throw ConfigException('${_k(key)} is required');
    }
    if (v is int) return v;
    throw ConfigException('${_k(key)} must be an integer');
  }

  bool boolean(String key, bool def) {
    final v = _get(key);
    if (v == null) return def;
    if (v is bool) return v;
    throw ConfigException('${_k(key)} must be true or false');
  }

  List<String> strs(String key, [List<String> def = const []]) {
    final v = _get(key);
    if (v == null) return def;
    if (v is String) return [v];
    if (v is YamlList) return [for (final x in v) '$x'];
    throw ConfigException('${_k(key)} must be a list of strings');
  }

  _Reader map(String key) {
    final v = _get(key);
    if (v == null) return _Reader(null, _k(key));
    if (v is YamlMap) return _Reader(v, _k(key));
    throw ConfigException('${_k(key)} must be a map');
  }

  List<_Reader> maps(String key) {
    final v = _get(key);
    if (v == null) return const [];
    if (v is! YamlList) throw ConfigException('${_k(key)} must be a list');
    return [
      for (final (i, x) in v.indexed)
        if (x is YamlMap)
          _Reader(x, '${_k(key)}[$i]')
        else
          throw ConfigException('${_k(key)}[$i] must be a map'),
    ];
  }

  Map<String, String> strMap(String key) {
    final m = map(key);
    return {for (final k in m.keys) k: m.str(k)};
  }

  Map<String, int> portMap(String key) {
    final m = map(key);
    return {for (final k in m.keys) k: m._get(k) == 'auto' ? 0 : m.integer(k)};
  }
}
