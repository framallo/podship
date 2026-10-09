// podship watch: the fleet (from ~/.podship/config.yaml), the targets that
// `watch install` writes into each machine's registry, and the scripts
// behind `watch status` and `watch history`.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';
import '../plan/plan.dart';
import '../remote/ssh.dart';
import '../server/registry.dart';
import '../watch/model.dart';
import 'context.dart';
import 'resolve.dart';
import 'scheduler_ops.dart';

/// One machine of the fleet: it runs a scheduler agent and watches.
class FleetMachine {
  FleetMachine({
    required this.name,
    required this.host,
    required this.home,
    this.path,
    this.engine = Engine.auto,
    String? ssh,
  }) : ssh = ssh ?? (isLocalHost(host) ? null : host);

  final String name;

  /// How the other machines reach this one with ssh (its heartbeat). For
  /// `host: local`, set `ssh:` (an alias with a restricted key).
  final String? ssh;

  String get heartbeatPath => '$home/watch/heartbeat.json';

  /// The ssh destination, or `local` for this machine.
  final String host;

  /// Its podship home (the registry's folder).
  final String home;

  /// Extra PATH entries on it (docker, colima).
  final String? path;
  final Engine engine;

  SchedulerTarget get target =>
      SchedulerTarget(host: host, home: home, remotePath: path);
}

/// `watch:` of `~/.podship/config.yaml` on the machine that runs the CLI:
/// the machines of the fleet and the settings every machine gets.
///
/// ```yaml
/// watch:
///   interval: 120
///   channels:
///     macos: {}
///     owner: {kind: email, to: [me@example.com], from: "podship <ops@example.com>", region: us-west-1}
///   machines:
///     studio:  {host: local, home: /Users/me/podship}
///     agentes: {host: agente@agentes.local, home: /Users/agente/podship, path: /Applications/Docker.app/Contents/Resources/bin}
/// ```
class FleetConfig {
  FleetConfig({
    this.machines = const [],
    this.interval = WatchSettings.defaultInterval,
    this.alertAfter = 2,
    this.healAttempts = 2,
    this.healBackoff = 360,
    this.channels = const {},
    this.consoleUrl,
  });

  final List<FleetMachine> machines;

  /// `watch.console`: the console whose AWS integration sends the email.
  final String? consoleUrl;
  final int interval;
  final int alertAfter;
  final int healAttempts;
  final int healBackoff;
  final Map<String, Map<String, Object?>> channels;

  static String get path =>
      p.join(Platform.environment['HOME'] ?? '.', '.podship', 'config.yaml');

  static FleetConfig load([String? file]) {
    final f = File(file ?? path);
    if (!f.existsSync()) return FleetConfig();
    final doc = loadYaml(f.readAsStringSync());
    if (doc is! YamlMap || doc['watch'] is! YamlMap) return FleetConfig();
    return parse(jsonDecode(jsonEncode(doc['watch'])) as Map);
  }

  static FleetConfig parse(Map w) {
    final machines = <FleetMachine>[];
    for (final e in ((w['machines'] as Map?) ?? const {}).entries) {
      final m = e.value as Map;
      if (m['host'] == null || m['home'] == null) {
        throw ConfigException('watch.machines.${e.key} needs host and home');
      }
      machines.add(
        FleetMachine(
          name: '${e.key}',
          host: '${m['host']}',
          home: '${m['home']}',
          path: m['path'] as String?,
          engine: Engine.parse(m['engine'] as String?),
          ssh: m['ssh'] as String?,
        ),
      );
    }
    final channels = <String, Map<String, Object?>>{
      for (final e in ((w['channels'] as Map?) ?? const {}).entries)
        '${e.key}': ((e.value as Map?) ?? const {}).cast<String, Object?>(),
    };
    return FleetConfig(
      machines: machines,
      interval:
          (w['interval'] as num?)?.toInt() ?? WatchSettings.defaultInterval,
      alertAfter: (w['alert_after'] as num?)?.toInt() ?? 2,
      healAttempts: (w['heal_attempts'] as num?)?.toInt() ?? 2,
      healBackoff: (w['heal_backoff'] as num?)?.toInt() ?? 360,
      channels: channels,
      consoleUrl: w['console'] as String?,
    );
  }

  /// The machine [env] runs on: the fleet machine with its host, else one
  /// made from the environment.
  FleetMachine ownerOf(EnvConfig env) =>
      machines
          .where(
            (m) =>
                m.host == env.host ||
                (isLocalHost(m.host) && isLocalHost(env.host)),
          )
          .firstOrNull ??
      FleetMachine(
        name: isLocalHost(env.host) ? Platform.localHostname : env.host,
        host: env.host,
        home: env.podshipHome,
        path: env.remotePath,
      );

  /// Every machine that watches [env]: its owner first, then the others.
  List<FleetMachine> watchersOf(EnvConfig env) {
    final owner = ownerOf(env);
    return [
      owner,
      for (final m in machines)
        if (m.name != owner.name) m,
    ];
  }

  /// Applies the fleet's settings to the registry of [m].
  void applyTo(WatchSettings w, FleetMachine m) {
    w
      ..machine = m.name
      ..interval = interval
      ..alertAfter = alertAfter
      ..healAttempts = healAttempts
      ..healBackoff = healBackoff
      ..engine = m.engine
      ..consoleUrl = consoleUrl;
    w.channels
      ..clear()
      ..addAll(channels);
  }
}

/// The checks of [r]: `health.public_checks`, else the `public_url` (any
/// 2xx). Empty: the environment has no public URL to watch.
List<WatchCheck> watchChecks(ResolvedEnv r) {
  final env = r.env;
  if (env.health.publicChecks.isNotEmpty) {
    return [
      for (final c in env.health.publicChecks)
        WatchCheck(
          url: r.sub(c.url),
          method: c.method,
          status: c.status,
          contentType: c.contentType,
          contains: c.contains,
        ),
    ];
  }
  final pub = r.publicHealthUrl;
  return pub == null ? const [] : [WatchCheck(url: pub)];
}

/// The target of [r] on its own machine (it may heal).
WatchTarget ownerTarget(
  Ctx ctx,
  ResolvedEnv r, {
  required FleetMachine owner,
  required String now,
}) {
  final env = r.env;
  return WatchTarget(
    project: ctx.config.project,
    env: env.name,
    checks: watchChecks(r),
    owner: true,
    machine: owner.name,
    heal: env.watch.heal,
    localUrls: r.healthUrls,
    releaseDir: p.posix.join(env.dir, 'current'),
    path: env.remotePath ?? owner.path,
    serverService: env.serverService,
    updated: now,
  );
}

/// The copy of [t] for another machine: it alerts only when the heartbeat
/// of [owner] is stale.
WatchTarget mirrorTarget(WatchTarget t, {FleetMachine? owner}) => WatchTarget(
  project: t.project,
  env: t.env,
  checks: t.checks,
  owner: false,
  machine: t.machine,
  heal: false,
  heartbeatHost: owner?.ssh,
  heartbeatPath: owner?.ssh == null ? null : owner!.heartbeatPath,
  updated: t.updated,
);

/// Plans `watch install` (or `uninstall` with [remove]) for [envs]: one
/// registry write per machine of the fleet.
Future<Plan> planWatchInstall(
  Ctx ctx,
  FleetConfig fleet,
  List<EnvConfig> envs, {
  bool remove = false,
  required String now,
}) async {
  final machines = <String, FleetMachine>{};
  final texts = <String, String>{};
  final regs = <String, Registry>{};
  Future<Registry> regOf(FleetMachine m) async {
    if (!regs.containsKey(m.name)) {
      machines[m.name] = m;
      texts[m.name] = await readRegistryText(ctx, m.target);
      regs[m.name] = Registry.parse(texts[m.name]!);
    }
    return regs[m.name]!;
  }

  final notes = <String>[];
  for (final env in envs) {
    if (!remove &&
        env.health.publicChecks.isEmpty &&
        env.health.publicUrl == null) {
      notes.add(
        '${ctx.config.project}/${env.name}: no public_url or public_checks; skipped',
      );
      continue;
    }
    final owner = fleet.ownerOf(env);
    final ownerReg = await regOf(owner);
    final key = '${ctx.config.project}/${env.name}';
    if (remove || !env.watch.enabled) {
      for (final m in fleet.watchersOf(env)) {
        (await regOf(m)).watch.targets.remove(key);
      }
      notes.add('$key: not watched');
      continue;
    }
    final r = resolveEnv(ctx.config, env, ownerReg);
    final t = ownerTarget(ctx, r, owner: owner, now: now);
    if (t.checks.isEmpty) {
      notes.add('$key: no public_url or public_checks; skipped');
      continue;
    }
    for (final m in fleet.watchersOf(env)) {
      final reg = await regOf(m);
      reg.watch.targets[key] = m.name == owner.name
          ? t
          : mirrorTarget(t, owner: owner);
    }
    notes.add(
      '$key: ${t.checks.length} check(s); heals on ${owner.name}: ${t.heal ? 'yes' : 'no'}; '
      'cross-watch from ${[for (final m in fleet.watchersOf(env))
        if (m.name != owner.name) m.name].join(', ').ifEmpty('none')}',
    );
  }
  final steps = <Step>[];
  for (final name in regs.keys) {
    final m = machines[name]!;
    final reg = regs[name]!;
    if (fleet.machines.isNotEmpty) fleet.applyTo(reg.watch, m);
    reg.watch.machine ??= m.name;
    final next = reg.render();
    if (next == texts[name]) continue;
    steps.add(
      RegistryWriteStep(
        'Write the watch targets into ${m.target.registryPath} on ${m.name}',
        m.host,
        m.target.registryPath,
        header: m.target.header(),
        base: texts[name]!,
        mine: next,
      ),
    );
  }
  for (final n in notes) {
    ctx.log.info(n);
  }
  return Plan(
    '${remove ? 'stop watching' : 'watch'} ${envs.map((e) => e.name).join(', ')}',
    steps,
  );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Prints the watch of a machine: its registry, its state and the last
/// [n] incident events. Parsed by [parseWatchStatus].
String watchStatusScript(String home, {int n = 20}) =>
    '''
echo "REGISTRY-BEGIN"
cat ${shq('$home/registry.yaml')} 2>/dev/null || true
echo "REGISTRY-END"
echo "STATE-BEGIN"
cat ${shq('$home/watch/state.json')} 2>/dev/null || true
echo "STATE-END"
echo "EVENTS-BEGIN"
tail -n $n ${shq('$home/watch/incidents.jsonl')} 2>/dev/null || true
echo "EVENTS-END"
echo "LOG-BEGIN"
tail -n 3 ${shq('$home/log/watch.log')} 2>/dev/null || true
echo "LOG-END"
''';

/// The watch of one machine, as `watch status` and `watch history` show it.
class WatchMachineStatus {
  WatchMachineStatus({
    required this.machine,
    required this.watch,
    required this.state,
    required this.events,
    required this.log,
    this.error,
  });

  final String machine;
  final WatchSettings watch;
  final Map<String, Object?> state;
  final List<Map<String, Object?>> events;
  final List<String> log;

  /// The machine did not answer.
  final String? error;

  Map<String, Object?> toJson() => {
    'machine': machine,
    if (error != null) 'error': error,
    'settings': watch.settingsMap()..remove('channels'),
    'channels': watch.channels.keys.toList(),
    'targets': [
      for (final t in watch.targets.values)
        {
          ...t.toMap(),
          ...?((state['targets'] as Map?)?[t.key] as Map?)
              ?.cast<String, Object?>(),
        },
    ],
    'last_run': state['last_run'],
    'events': events,
    'log': log,
  };
}

WatchMachineStatus parseWatchStatus(String out, {required String machine}) {
  final parts = <String, StringBuffer>{};
  String? section;
  for (final line in const LineSplitter().convert(out)) {
    if (section != null) {
      if (line == '$section-END') {
        section = null;
      } else {
        parts.putIfAbsent(section, StringBuffer.new).writeln(line);
      }
      continue;
    }
    if (line.endsWith('-BEGIN')) section = line.substring(0, line.length - 6);
  }
  final reg = Registry.parse(parts['REGISTRY']?.toString() ?? '');
  Map<String, Object?> state = const {};
  try {
    final j = jsonDecode(parts['STATE']?.toString() ?? '');
    if (j is Map) state = j.cast<String, Object?>();
  } catch (_) {}
  final events = <Map<String, Object?>>[];
  for (final l in const LineSplitter().convert(
    parts['EVENTS']?.toString() ?? '',
  )) {
    try {
      final j = jsonDecode(l);
      if (j is Map) events.add(j.cast<String, Object?>());
    } catch (_) {}
  }
  return WatchMachineStatus(
    machine: machine,
    watch: reg.watch,
    state: state,
    events: events,
    log: const LineSplitter()
        .convert(parts['LOG']?.toString() ?? '')
        .where((l) => l.trim().isNotEmpty)
        .toList(),
  );
}

/// The watch of [m]. A machine that does not answer gives an error entry.
Future<WatchMachineStatus> watchStatus(
  Ctx ctx,
  FleetMachine m, {
  int n = 20,
}) async {
  try {
    return parseWatchStatus(
      await m.target.query(ctx, watchStatusScript(m.home, n: n)),
      machine: m.name,
    );
  } catch (e) {
    return WatchMachineStatus(
      machine: m.name,
      watch: WatchSettings(),
      state: const {},
      events: const [],
      log: const [],
      error: '$e'.split('\n').first,
    );
  }
}
