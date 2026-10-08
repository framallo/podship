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
    this.inputs = const [],
    this.reuse = true,
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

  /// More paths (relative to the project root) whose changes need a new
  /// build. The package folder, its `path:` dependencies and the nearest
  /// `pubspec.lock` always count.
  final List<String> inputs;

  /// Whether a release may take the build of an earlier release whose
  /// inputs have the same hash, instead of building again.
  final bool reuse;
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

class GitHubConfig {
  GitHubConfig({
    required this.repo,
    this.tags = true,
    this.deployments = true,
    this.statuses = true,
    this.releases = const ['production'],
    this.releaseTag = 'v{date}-{n}',
  });

  /// `owner/name`.
  final String repo;

  /// Push `podship/<env>/<release>` tags.
  final bool tags;

  /// Create GitHub Deployments with status updates.
  final bool deployments;

  /// Set a `podship/deploy/<env>` commit status.
  final bool statuses;

  /// Environments whose deploys create a GitHub Release.
  final List<String> releases;

  /// The release tag scheme: `{date}` is YYYY.MM.DD, `{n}` counts releases
  /// of that day from 1.
  final String releaseTag;
}

/// An outbound proxy for some containers, for example to leave from a
/// Mexican address while the app runs elsewhere.
///
/// `applies_to` lists compose services; every one gets `HTTPS_PROXY`,
/// `HTTP_PROXY` and `ALL_PROXY`. A service named `chrome` also gets
/// `PODSHIP_CHROME_PROXY`, for an entrypoint that passes it to Chrome's
/// `--proxy-server`.
class EgressConfig {
  EgressConfig({
    required this.proxy,
    this.appliesTo = const ['chrome'],
    this.noProxy = const [],
  });

  /// Like `socks5://user:pass@host:1080` or `http://host:3128`. Put a
  /// proxy with a password in a secret and write `${NAME}` here.
  final String proxy;
  final List<String> appliesTo;
  final List<String> noProxy;
}

/// Serverpod operations settings of an environment.
class ServerpodSettings {
  ServerpodSettings({
    this.readiness = true,
    this.readinessUrl,
    this.logRetentionPeriod,
    this.logRetentionCount,
    this.logCleanupInterval,
    this.persistentLogs,
    this.consoleLogs,
    this.replicas = 1,
    this.redis = false,
    this.dbPool,
    this.stopGraceSeconds = 30,
    this.exceptionDsnEnv,
    this.replicaEntrypoint,
  });

  /// Also gate deploys on Serverpod's `/readyz`.
  final bool readiness;

  /// The readiness URL on the server. Default: `/readyz` on the `web` port,
  /// else on the `api` port.
  final String? readinessUrl;

  /// Session log retention, like `30d` (SERVERPOD_SESSION_LOG_RETENTION_PERIOD).
  final String? logRetentionPeriod;

  /// At most this many session log rows (SERVERPOD_SESSION_LOG_RETENTION_COUNT).
  final int? logRetentionCount;

  /// How often old logs are deleted, like `24h`.
  final String? logCleanupInterval;
  final bool? persistentLogs;
  final bool? consoleLogs;

  /// Server containers. Above 1, podship adds `server-replica` containers
  /// with the serverless role, a load balancer with sticky sessions for
  /// streams, and Redis.
  final int replicas;

  /// Run Redis for this environment (always when replicas > 1).
  final bool redis;

  /// Database connections per server container.
  final int? dbPool;

  /// Seconds a server gets to finish requests when it stops (Serverpod
  /// drains on SIGTERM).
  final int stopGraceSeconds;

  /// The `.env` variable that holds the exception monitoring DSN (for
  /// example SENTRY_DSN), checked by `doctor`. The app reports to it.
  final String? exceptionDsnEnv;

  /// The entrypoint of replicas, when the compose file pins `--role` in
  /// the server's entrypoint.
  final List<String>? replicaEntrypoint;

  bool get needsRedis => redis || replicas > 1;

  /// Environment variables for every server container.
  Map<String, String> get environment => {
    'SERVERPOD_SESSION_LOG_RETENTION_PERIOD': ?logRetentionPeriod,
    if (logRetentionCount != null)
      'SERVERPOD_SESSION_LOG_RETENTION_COUNT': '$logRetentionCount',
    'SERVERPOD_SESSION_LOG_CLEANUP_INTERVAL': ?logCleanupInterval,
    if (persistentLogs != null)
      'SERVERPOD_SESSION_PERSISTENT_LOG_ENABLED': '$persistentLogs',
    if (consoleLogs != null)
      'SERVERPOD_SESSION_CONSOLE_LOG_ENABLED': '$consoleLogs',
    if (dbPool != null) 'SERVERPOD_DATABASE_MAX_CONNECTION_COUNT': '$dbPool',
    if (needsRedis) ...{
      'SERVERPOD_REDIS_ENABLED': 'true',
      'SERVERPOD_REDIS_HOST': 'redis',
      'SERVERPOD_REDIS_PORT': '6379',
    },
  };
}

/// One test suite that runs during a deploy.
class TestSuite {
  TestSuite({
    required this.name,
    required this.dir,
    required this.command,
    this.timeoutSeconds = 1800,
    this.environments = const [],
    this.image,
    this.inputs = const [],
    this.skipUnchanged = true,
  });

  final String name;

  /// The working directory, relative to the project root.
  final String dir;

  /// A shell command, like `dart test --concurrency=1` or `flutter test`.
  final String command;
  final int timeoutSeconds;

  /// The environments it runs for. Empty means all.
  final List<String> environments;

  /// The Docker image for `runner: container` (like `dart:stable`).
  final String? image;

  /// More paths (relative to the project root) whose changes need a new
  /// run. [dir], its `path:` dependencies and the nearest `pubspec.lock`
  /// always count.
  final List<String> inputs;

  /// Whether the suite is skipped when its inputs have the hash of a run
  /// that passed before (`deploy --full-tests` runs it anyway).
  final bool skipUnchanged;

  bool runsFor(String env) =>
      environments.isEmpty || environments.contains(env);
}

/// Where tests run.
enum TestRunner {
  /// On the machine that runs podship (a laptop or CI).
  local,

  /// In a throwaway container on the environment's server, from the
  /// uploaded release files, before the images are built.
  container,
}

class TestsConfig {
  TestsConfig({
    this.runner = TestRunner.local,
    this.suites = const [],
    this.gate = const ['production'],
    this.parallel = true,
  });
  final TestRunner runner;
  final List<TestSuite> suites;

  /// Environments that only take a commit whose tests passed (in this
  /// deploy, or in another environment's deploy of the same commit).
  final List<String> gate;

  /// Whether the suites run at the same time (each in its own folder).
  final bool parallel;

  List<TestSuite> forEnv(String env) => [
    for (final s in suites)
      if (s.runsFor(env)) s,
  ];
}

/// Something that happened and may be announced.
enum NotifyEvent {
  deployStarted('deploy_started'),
  deployDone('deploy_done'),
  deployFailed('deploy_failed'),
  rollbackDone('rollback_done'),
  backupFailed('backup_failed'),
  schedulerJobFailed('scheduler_job_failed');

  const NotifyEvent(this.id);

  /// The name in `podship.yaml` and in JSON.
  final String id;

  static NotifyEvent? parse(String s) =>
      values.where((e) => e.id == s).firstOrNull;

  /// Every event but `deploy_started`.
  static const defaults = [
    deployDone,
    deployFailed,
    rollbackDone,
    backupFailed,
    schedulerJobFailed,
  ];
}

/// One notification channel.
class NotifyChannel {
  NotifyChannel({
    required this.name,
    required this.kind,
    this.events,
    this.url,
    this.secret,
    this.to = const [],
    this.from,
    this.region,
  });

  /// The key under `notify.channels`.
  final String name;

  /// `macos`, `email`, `webhook` or `slack`.
  final String kind;

  /// The events this channel gets. Null: the events of `notify.events`.
  final List<NotifyEvent>? events;

  /// The webhook or Slack URL. A URL that carries a token belongs in
  /// `~/.podship/config.yaml`, not in the committed `podship.yaml`.
  final String? url;

  /// The HMAC secret of a webhook. From `~/.podship/config.yaml` or the
  /// variable named in `secret_env` (default `PODSHIP_WEBHOOK_SECRET`).
  final String? secret;

  /// Email recipients.
  final List<String> to;

  /// The email sender (default: the environment's `email.from`).
  final String? from;

  /// The SES region (default: the environment's `email.region`).
  final String? region;

  static const kinds = ['macos', 'email', 'webhook', 'slack'];

  bool wants(NotifyEvent e, List<NotifyEvent> defaults) =>
      (events ?? defaults).contains(e);

  NotifyChannel merge(NotifyChannel over) => NotifyChannel(
    name: name,
    kind: over.kind,
    events: over.events ?? events,
    url: over.url ?? url,
    secret: over.secret ?? secret,
    to: over.to.isEmpty ? to : over.to,
    from: over.from ?? from,
    region: over.region ?? region,
  );
}

/// `notify:` — which events reach which channels. The project file and
/// `~/.podship/config.yaml` both may have one; the project's settings win,
/// channel by channel.
class NotifyConfig {
  NotifyConfig({
    List<NotifyEvent>? events,
    this.channels = const [],
    this.bell = true,
    this.enabled = true,
  }) : events = events ?? NotifyEvent.defaults;

  /// The events channels get unless they list their own.
  final List<NotifyEvent> events;
  final List<NotifyChannel> channels;

  /// A terminal bell when a long command ends.
  final bool bell;

  /// `enabled: false` turns every channel off (`--notify` turns it on).
  final bool enabled;

  NotifyChannel? channel(String name) =>
      channels.where((c) => c.name == name).firstOrNull;

  /// This config on top of [base] (the global one).
  NotifyConfig over(NotifyConfig? base, {bool eventsSet = true}) {
    if (base == null) return this;
    final merged = <String, NotifyChannel>{
      for (final c in base.channels) c.name: c,
    };
    for (final c in channels) {
      final b = merged[c.name];
      merged[c.name] = b == null ? c : b.merge(c);
    }
    return NotifyConfig(
      events: eventsSet ? events : base.events,
      channels: merged.values.toList(),
      bell: bell,
      enabled: enabled,
    );
  }

  /// Reads `~/.podship/config.yaml` (or `$PODSHIP_HOME/config.yaml`), or
  /// null when there is none.
  static NotifyConfig? global({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final home = env['PODSHIP_HOME'] ?? p.join(env['HOME'] ?? '', '.podship');
    final f = File(p.join(home, 'config.yaml'));
    if (!f.existsSync()) return null;
    final Object? doc;
    try {
      doc = loadYaml(f.readAsStringSync());
    } on YamlException catch (e) {
      throw ConfigException('${f.path}: $e');
    }
    if (doc is! YamlMap) return null;
    return _parseNotify(_Reader(doc, '').map('notify'), env);
  }
}

NotifyConfig _parseNotify(_Reader n, Map<String, String> env) {
  final events = [
    for (final s in n.strs('events', [
      for (final e in NotifyEvent.defaults) e.id,
    ]))
      NotifyEvent.parse(s) ??
          (throw ConfigException(
            'notify.events: unknown "$s" (${NotifyEvent.values.map((e) => e.id).join(', ')})',
          )),
  ];
  final ch = n.map('channels');
  final channels = <NotifyChannel>[];
  for (final name in ch.keys) {
    final c = ch.map(name);
    final kind = c.str('kind', NotifyChannel.kinds.contains(name) ? name : '');
    if (!NotifyChannel.kinds.contains(kind)) {
      throw ConfigException(
        'notify.channels.$name: kind must be one of ${NotifyChannel.kinds.join(', ')}',
      );
    }
    final secretEnv = c.str('secret_env', 'PODSHIP_WEBHOOK_SECRET');
    final urlEnv = c.optStr('url_env');
    channels.add(
      NotifyChannel(
        name: name,
        kind: kind,
        events: c.has('events')
            ? [
                for (final s in c.strs('events'))
                  NotifyEvent.parse(s) ??
                      (throw ConfigException(
                        'notify.channels.$name.events: unknown "$s"',
                      )),
              ]
            : null,
        url: (urlEnv == null ? null : env[urlEnv]) ?? c.optStr('url'),
        secret: env[secretEnv] ?? c.optStr('secret'),
        to: c.strs('to'),
        from: c.optStr('from'),
        region: c.optStr('region'),
      ),
    );
  }
  return NotifyConfig(
    events: events,
    // Without a channels: block, the machine that runs the CLI gets a
    // desktop notification (the channel does nothing outside macOS).
    channels: n.has('channels')
        ? channels
        : [NotifyChannel(name: 'macos', kind: 'macos')],
    bell: n.boolean('bell', true),
    enabled: n.boolean('enabled', true),
  );
}

/// Compose settings shared by all environments.
class ComposeConfig {
  ComposeConfig({
    this.files = const ['docker-compose.yml'],
    this.buildContexts = const {},
    this.remotePreBuild = const [],
    this.remotePostSwitch = const [],
  });

  /// Compose files, relative to the project root. They are shipped.
  final List<String> files;

  /// Build contexts that live on the server and are not shipped, keyed by
  /// service, like `pacewright: /srv/pacewright`.
  final Map<String, String> buildContexts;

  /// Shell commands that run on the server before the build.
  final List<String> remotePreBuild;

  /// Shell commands that run on the server in the new release's folder
  /// after the switch and the health check, like installing a host service
  /// (a launchd agent) that runs next to the containers. A failure rolls
  /// the deploy back.
  final List<String> remotePostSwitch;
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
    this.fallbackUrls = const [],
    this.publicFallbackUrls = const [],
    this.attempts = 20,
    this.intervalSeconds = 6,
  });

  /// A URL that is fetched ON THE SERVER, usually a loopback port.
  final String url;

  /// An optional public URL that is fetched from this machine.
  final String? publicUrl;

  /// Other URLs that also count as healthy, for releases made before the
  /// health route moved (a rollback to an old release still passes).
  final List<String> fallbackUrls;
  final List<String> publicFallbackUrls;
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
  DomainConfig({required this.host, required this.routes, this.access});
  final String host;
  final List<DomainRoute> routes;

  /// A Cloudflare Access app in front of the host, when set.
  final AccessConfig? access;
}

/// Who may pass a Cloudflare Access app.
class AccessConfig {
  AccessConfig({
    this.emails = const [],
    this.emailDomains = const [],
    this.sessionDuration = '24h',
  });
  final List<String> emails;
  final List<String> emailDomains;
  final String sessionDuration;
}

/// How DNS records are managed.
enum DnsProvider { none, cloudflare }

/// `dns:` of an environment.
class DnsConfig {
  DnsConfig({
    this.provider = DnsProvider.none,
    this.zone,
    this.accountId,
    this.ipv4,
    this.ipv6,
    this.proxied,
  });

  /// `none`: podship prints the records to create. `cloudflare`: podship
  /// creates them through the API (after a plan and an approval).
  final DnsProvider provider;

  /// The zone (default: the longest zone in the account that the host
  /// ends with).
  final String? zone;

  /// The Cloudflare account (default: the zone's account).
  final String? accountId;

  /// With Caddy, the server's addresses for A and AAAA records.
  final String? ipv4;
  final String? ipv6;

  /// With Caddy: proxy A/AAAA records through Cloudflare (default false,
  /// so Caddy's ACME challenge reaches the server).
  final bool? proxied;
}

/// `email:` of an environment: the sender of the app.
class EmailConfig {
  EmailConfig({
    required this.from,
    required this.region,
    this.provider = 'ses',
    this.identity,
    this.mailFrom,
    this.envNames = const {},
  });

  /// `Name <hola@app.example>` or an address.
  final String from;

  /// The SES region, like us-west-1.
  final String region;
  final String provider;

  /// The SES identity to create when none can send (default: the from
  /// address's domain).
  final String? identity;

  /// A custom MAIL FROM subdomain, like bounce.app.example.
  final String? mailFrom;

  /// Variable names for the app (`from`, `region`, `provider`).
  final Map<String, String> envNames;

  /// The address part of [from].
  String get address {
    final m = RegExp(r'<([^>]+)>').firstMatch(from);
    return (m?.group(1) ?? from).trim();
  }

  /// The domain of the from address.
  String get domain => address.substring(address.lastIndexOf('@') + 1);

  /// The variables podship gives the server container at deploy. No
  /// credentials: the app's own sending keys stay in its secrets.
  Map<String, String> get environment => {
    envNames['from'] ?? 'EMAIL_FROM': from,
    envNames['region'] ?? 'SES_REGION': region,
    envNames['provider'] ?? 'EMAIL_PROVIDER': provider,
  };
}

/// The reverse proxy in front of an environment.
enum ProxyKind { cloudflareTunnel, caddy, none }

class ProxyConfig {
  ProxyConfig({
    this.kind = ProxyKind.none,
    this.config,
    this.service,
    this.tunnelId,
    this.originCerts = const {},
    this.managed,
  });
  final ProxyKind kind;

  /// For a Cloudflare Tunnel: `remote` (ingress managed through the
  /// Cloudflare API) or `local` (a config.yml on the host). Default: local
  /// when [config] is set, else remote.
  final String? managed;

  /// Whether the tunnel's ingress is managed through the API.
  bool get remoteManaged =>
      kind == ProxyKind.cloudflareTunnel &&
      (managed == 'remote' || (managed == null && config == null));

  /// Cloudflare origin certificates on the server, by zone, for
  /// `cloudflared tunnel route dns`.
  final Map<String, String> originCerts;

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
    this.owner,
  });

  /// The archive name, like `pacewright` → `pacewright.tar.zst`.
  final String name;

  /// The Docker volume name.
  final String volume;

  /// SQLite files that are copied with SQLite's backup API.
  final List<String> sqlite;

  /// Other files to copy. Empty means the whole volume.
  final List<String> files;

  /// `uid:gid` that owns the volume's files after a restore, like
  /// `10001:10001` for a daemon that does not run as root.
  final String? owner;
}

/// File and folder names inside the backup directory.
class BackupLayout {
  BackupLayout({
    this.plain = 'daily',
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
    this.replaces = const [],
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

  /// Older scheduled backup units (systemd timers or launchd labels) that
  /// this schedule replaces. `backup schedule` disables them and leaves
  /// their files, so one environment never has two schedules.
  final List<String> replaces;
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
    this.remotePostSwitch,
    this.scheduler = Scheduler.auto,
    this.transport,
    ServerpodSettings? serverpod,
    this.egress,
    DnsConfig? dns,
    this.email,
  }) : dns = dns ?? DnsConfig(),
       serverpod = serverpod ?? ServerpodSettings(),
       secrets = secrets ?? SecretsConfig(),
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

  /// Overrides `compose.remote_post_switch` for this environment.
  final List<String>? remotePostSwitch;

  /// How scheduled backups run on the server.
  final Scheduler scheduler;

  /// `ssh` or `console` for this environment; null means the project's.
  final String? transport;

  /// Serverpod operations settings: logs, readiness, replicas, Redis.
  final ServerpodSettings serverpod;

  /// An outbound proxy for some containers (see [EgressConfig]).
  final EgressConfig? egress;

  /// How DNS records are managed (Cloudflare API, or printed).
  final DnsConfig dns;

  /// The app's email sender (SES), when set.
  final EmailConfig? email;

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
    TestsConfig? tests,
    this.consoleUrl,
    this.transport = 'ssh',
    this.github,
    NotifyConfig? notify,
  }) : tests = tests ?? TestsConfig(),
       notify = notify ?? NotifyConfig();

  /// GitHub on every release, when set.
  final GitHubConfig? github;

  /// Notifications: the project's `notify:` on top of the one in
  /// `~/.podship/config.yaml`.
  final NotifyConfig notify;

  /// The podship console of this project, if there is one.
  final String? consoleUrl;

  /// `ssh` (default) or `console`: how commands run unless `--via` says
  /// otherwise. An environment can set its own.
  final String transport;

  /// The test stage of deploys.
  final TestsConfig tests;

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

  /// Reads `podship.yaml` from [dir] or its parents, and the global
  /// `~/.podship/config.yaml` under it.
  static PodshipConfig load([String? dir]) {
    var d = Directory(dir ?? Directory.current.path).absolute;
    while (true) {
      final f = File(p.join(d.path, configFileName));
      if (f.existsSync()) {
        return parse(
          f.readAsStringSync(),
          root: d.path,
          globalNotify: NotifyConfig.global(),
        );
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

  /// Parses the YAML text of `podship.yaml`. [globalNotify] is the
  /// `notify:` of `~/.podship/config.yaml`, under the project's own.
  static PodshipConfig parse(
    String text, {
    String root = '.',
    NotifyConfig? globalNotify,
    Map<String, String>? environment,
  }) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw ConfigException('$e');
    }
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
            inputs: m.strs('inputs'),
            reuse: m.boolean('reuse', true),
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
      remotePostSwitch: c.strs('remote_post_switch'),
    );

    final envs = <String, EnvConfig>{};
    final em = r.map('environments');
    if (em.keys.isEmpty) {
      throw ConfigException('environments: define at least one');
    }
    for (final name in em.keys) {
      envs[name] = _parseEnv(
        name,
        em.map(name),
        project,
        serverPackage,
        r.map('cloudflare').optStr('account_id'),
      );
    }
    _checkIsolation(envs.values.toList());

    final t = r.map('tests');
    final tests = TestsConfig(
      runner: switch (t.str('runner', 'local')) {
        'local' => TestRunner.local,
        'container' => TestRunner.container,
        final x => throw ConfigException('tests.runner: unknown "$x"'),
      },
      gate: t.strs('gate', const ['production']),
      parallel: t.boolean('parallel', true),
      suites: [
        for (final m in t.maps('suites'))
          TestSuite(
            name: m.str('name'),
            dir: m.str('dir', '.'),
            command: m.str('command'),
            timeoutSeconds: m.integer('timeout', 1800),
            environments: m.strs('environments'),
            image: m.optStr('image'),
            inputs: m.strs('inputs'),
            skipUnchanged: m.boolean('skip_unchanged', true),
          ),
      ],
    );
    final notifyReader = r.map('notify');
    final notify = _parseNotify(
      notifyReader,
      environment ?? Platform.environment,
    ).over(globalNotify, eventsSet: notifyReader.has('events'));
    for (final s in tests.suites) {
      for (final e in s.environments) {
        if (!envs.containsKey(e)) {
          throw ConfigException(
            'tests suite ${s.name}: unknown environment "$e"',
          );
        }
      }
    }

    final transport = r.str('transport', 'ssh');
    if (!const ['ssh', 'console'].contains(transport)) {
      throw ConfigException('transport must be ssh or console');
    }
    final gh = r.map('github');
    final github = r.has('github')
        ? GitHubConfig(
            repo: gh.str('repo'),
            tags: gh.boolean('tags', true),
            deployments: gh.boolean('deployments', true),
            statuses: gh.boolean('statuses', true),
            releases: gh.strs('releases', const ['production']),
            releaseTag: gh.str('release_tag', 'v{date}-{n}'),
          )
        : null;
    return PodshipConfig(
      github: github,
      notify: notify,
      consoleUrl: r.map('console').optStr('url'),
      transport: transport,
      tests: tests,
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
    String serverPackage, [
    String? cloudflareAccount,
  ]) {
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
              owner: v.optStr('owner'),
            ),
        ],
        layout: BackupLayout(
          plain: l.str('plain', 'daily'),
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
        replaces: bk.strs('replaces'),
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
        fallbackUrls: h.strs('fallback_urls'),
        publicFallbackUrls: h.strs('public_fallback_urls'),
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
        originCerts: px.strMap('origin_certs'),
        managed: switch (px.optStr('managed')) {
          null || 'remote' || 'local' => px.optStr('managed'),
          final m => throw ConfigException(
            'environments.$name.proxy.managed: unknown "$m" (remote or local)',
          ),
        },
      ),
      dns: () {
        final d = e.map('dns');
        return DnsConfig(
          provider: switch (d.str('provider', 'none')) {
            'none' => DnsProvider.none,
            'cloudflare' => DnsProvider.cloudflare,
            final x => throw ConfigException(
              'environments.$name.dns.provider: unknown "$x" (cloudflare or none)',
            ),
          },
          zone: d.optStr('zone'),
          accountId: d.optStr('account_id') ?? cloudflareAccount,
          ipv4: d.optStr('ipv4'),
          ipv6: d.optStr('ipv6'),
          proxied: d.has('proxied') ? d.boolean('proxied', false) : null,
        );
      }(),
      email: () {
        if (!e.has('email')) return null;
        final m = e.map('email');
        final provider = m.str('provider', 'ses');
        if (provider != 'ses') {
          throw ConfigException(
            'environments.$name.email.provider: unknown "$provider" (ses)',
          );
        }
        final from = m.str('from');
        final addr = RegExp(r'<([^>]+)>').firstMatch(from)?.group(1) ?? from;
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(addr.trim())) {
          throw ConfigException(
            'environments.$name.email.from: "$from" has no valid address',
          );
        }
        return EmailConfig(
          from: from,
          region: m.str('region'),
          provider: provider,
          identity: m.optStr('identity'),
          mailFrom: m.optStr('mail_from'),
          envNames: m.strMap('env'),
        );
      }(),
      domains: [
        for (final dm in e.maps('domains'))
          DomainConfig(
            host: dm.str('host'),
            routes: [
              for (final rt in dm.maps('routes'))
                DomainRoute(path: rt.optStr('path'), port: rt.str('port')),
            ],
            access: dm.has('access')
                ? AccessConfig(
                    emails: dm.map('access').strs('emails'),
                    emailDomains: dm.map('access').strs('email_domains'),
                    sessionDuration: dm.map('access').str('session', '24h'),
                  )
                : null,
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
      remotePostSwitch: e.has('remote_post_switch')
          ? e.strs('remote_post_switch')
          : null,
      transport: e.optStr('transport'),
      serverpod: () {
        final sp = e.map('serverpod');
        final logs = sp.map('logs');
        return ServerpodSettings(
          readiness: sp.boolean('readiness', true),
          readinessUrl: sp.optStr('readiness_url'),
          logRetentionPeriod: logs.optStr('retention_period'),
          logRetentionCount: logs.has('retention_count')
              ? logs.integer('retention_count')
              : null,
          logCleanupInterval: logs.optStr('cleanup_interval'),
          persistentLogs: logs.has('persistent')
              ? logs.boolean('persistent', true)
              : null,
          consoleLogs: logs.has('console')
              ? logs.boolean('console', true)
              : null,
          replicas: sp.integer('replicas', 1),
          redis: sp.boolean('redis', false),
          dbPool: sp.has('db_pool') ? sp.integer('db_pool') : null,
          stopGraceSeconds: sp.integer('stop_grace', 30),
          exceptionDsnEnv: sp.optStr('exception_dsn_env'),
          replicaEntrypoint: sp.has('replica_entrypoint')
              ? sp.strs('replica_entrypoint')
              : null,
        );
      }(),
      egress: e.has('egress')
          ? EgressConfig(
              proxy: e.map('egress').str('proxy'),
              appliesTo: e.map('egress').strs('applies_to', const ['chrome']),
              noProxy: e.map('egress').strs('no_proxy', const [
                'localhost',
                '127.0.0.1',
              ]),
            )
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
