// One run of `podship watch` on a machine: the scheduler agent calls it at
// every tick (every `watch.interval` seconds), before the nightly jobs.
//
// It reads the `watch:` section of `<home>/registry.yaml`, runs the public
// checks of every target at the same time, feeds the results to the
// incident state machine (incident.dart), sends the alerts, and heals the
// targets that run on this machine: it starts the Docker engine when it
// does not answer, then runs `podship restart` for each failing
// environment (never a deploy). It keeps `<home>/watch/state.json` and
// appends every incident event to `<home>/watch/incidents.jsonl`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/events.dart' show LogLine;
import '../config/config.dart';
import '../integrations/ses.dart';
import '../notify/notify.dart';
import '../integrations/secrets.dart' show AwsCredentials;
import '../protocol/tokens.dart' show TokenStore;
import '../plan/executor.dart' show publicCheckProblem;
import '../scheduler/scheduler.dart' show podshipCommand;
import '../server/registry.dart';
import '../util/log.dart';
import 'heal.dart';
import 'incident.dart';
import 'model.dart';

/// Runs a program with a time limit; tests replace it.
typedef WatchProcess =
    Future<({int code, String out})> Function(
      String exe,
      List<String> args, {
      Map<String, String>? environment,
      String? cwd,
      Duration timeout,
    });

Future<({int code, String out})> runWithTimeout(
  String exe,
  List<String> args, {
  Map<String, String>? environment,
  String? cwd,
  Duration timeout = const Duration(minutes: 1),
}) async {
  try {
    final proc = await Process.start(
      exe,
      args,
      environment: environment,
      workingDirectory: cwd,
    );
    await proc.stdin.close();
    final out = StringBuffer();
    final pumps = [
      proc.stdout.transform(utf8.decoder).forEach(out.write),
      proc.stderr.transform(utf8.decoder).forEach(out.write),
    ];
    final code = await proc.exitCode.timeout(
      timeout,
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        out.write('\n(killed after ${timeout.inSeconds} s)');
        return 124;
      },
    );
    await Future.wait(
      pumps,
    ).timeout(const Duration(seconds: 5), onTimeout: () => []);
    return (code: code, out: out.toString());
  } on ProcessException catch (e) {
    return (code: 127, out: '$e');
  }
}

/// URLs that tell whether this machine reaches the internet at all. When
/// every one fails, a run says nothing about the targets.
const canaryUrls = [
  'https://www.google.com/generate_204',
  'https://1.1.1.1/cdn-cgi/trace',
];

/// Why [c] fails now, or null.
Future<String?> runCheck(WatchCheck c) => publicCheckProblem(
  PublicCheck(
    url: c.url,
    method: c.method,
    status: c.status,
    contentType: c.contentType,
    contains: c.contains,
  ),
);

Future<bool> internetUp() async {
  for (final u in canaryUrls) {
    if (await httpAnswers(u)) return true;
  }
  return false;
}

/// Any HTTP answer (a status, whatever it is).
Future<bool> httpAnswers(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.followRedirects = false;
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain<void>();
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Whether [url] answers 2xx.
Future<bool> http2xx(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 10));
    await res.drain<void>();
    return res.statusCode >= 200 && res.statusCode < 300;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// One event in `<home>/watch/incidents.jsonl`.
class IncidentEvent {
  IncidentEvent({
    required this.time,
    required this.event,
    required this.target,
    this.incident,
    this.machine,
    this.problem,
    this.ok,
    this.attempt,
    this.detail,
    this.downtime,
  });

  factory IncidentEvent.fromJson(Map m) => IncidentEvent(
    time: DateTime.tryParse('${m['time']}') ?? DateTime(1970),
    event: '${m['event']}',
    target: '${m['target']}',
    incident: m['incident'] as String?,
    machine: m['machine'] as String?,
    problem: m['problem'] as String?,
    ok: m['ok'] as bool?,
    attempt: (m['attempt'] as num?)?.toInt(),
    detail: m['detail'] as String?,
    downtime: m['downtime_s'] == null
        ? null
        : Duration(seconds: (m['downtime_s'] as num).toInt()),
  );

  final DateTime time;

  /// `down`, `engine_start`, `heal`, `still_down`, `recovered`.
  final String event;
  final String target;
  final String? incident;
  final String? machine;
  final String? problem;
  final bool? ok;
  final int? attempt;
  final String? detail;
  final Duration? downtime;

  Map<String, Object?> toJson() => {
    'time': time.toUtc().toIso8601String(),
    'event': event,
    'target': target,
    'incident': ?incident,
    'machine': ?machine,
    'problem': ?problem,
    'ok': ?ok,
    'attempt': ?attempt,
    'detail': ?detail,
    if (downtime != null) 'downtime_s': downtime!.inSeconds,
  };
}

/// `1 h 05 min`, `4 min 10 s`, `40 s`.
String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
  if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} s';
  return '$s s';
}

/// The notification channels of the watch, from the registry's
/// `watch.channels`. None: a macOS notification on this machine.
NotifyConfig watchNotifyConfig(WatchSettings w) {
  final channels = <NotifyChannel>[
    for (final e in w.channels.entries)
      NotifyChannel(
        name: e.key,
        kind: '${e.value['kind'] ?? e.key}',
        to: [for (final t in (e.value['to'] as List?) ?? const []) '$t'],
        from: e.value['from'] as String?,
        region: e.value['region'] as String?,
        url:
            e.value['url'] as String? ??
            (e.value['url_env'] == null
                ? null
                : Platform.environment['${e.value['url_env']}']),
        secret: e.value['secret_env'] == null
            ? null
            : Platform.environment['${e.value['secret_env']}'],
      ),
  ];
  return NotifyConfig(
    events: const [NotifyEvent.watchDown, NotifyEvent.watchRecovered],
    channels: channels.isEmpty
        ? [NotifyChannel(name: 'macos', kind: 'macos')]
        : channels,
    bell: false,
  );
}

/// The result of one run, for the log and the tests.
class WatchRun {
  WatchRun({
    required this.outcomes,
    required this.decisions,
    required this.events,
    required this.notifications,
    this.online = true,
  });
  final Map<String, Outcome> outcomes;
  final Map<String, Decision> decisions;
  final List<IncidentEvent> events;
  final List<Notification> notifications;
  final bool online;
}

/// Runs the watch of one machine.
class WatchRunner {
  WatchRunner(
    this.home, {
    DateTime Function()? clock,
    this.echo,
    Future<String?> Function(WatchCheck)? check,
    Future<bool> Function()? online,
    Future<bool> Function(String url)? localOk,
    WatchProcess? process,
    this.notifier,
    this.engineWait = const Duration(minutes: 3),
    this.localWait = const Duration(seconds: 90),
    this.pollEvery = const Duration(seconds: 5),
    String? machine,
    this.isMacos,
    Future<Map<String, Object?>?> Function(WatchTarget)? heartbeat,
    Future<AwsCredentials?> Function(String? url)? consoleAws,
  }) : _readHeartbeat = heartbeat,
       _consoleAws = consoleAws,
       clock = clock ?? DateTime.now,
       _check = check ?? runCheck,
       _online = online ?? internetUp,
       _localOk = localOk ?? http2xx,
       _process = process ?? runWithTimeout,
       _machine = machine;

  final String home;
  final DateTime Function() clock;
  final void Function(String line)? echo;
  final Future<String?> Function(WatchCheck) _check;
  final Future<bool> Function() _online;
  final Future<bool> Function(String url) _localOk;
  final WatchProcess _process;

  /// The notifier (tests); default: from the registry's channels.
  final Notifier? notifier;
  final Duration engineWait;
  final Duration localWait;
  final Duration pollEvery;
  final String? _machine;
  final bool? isMacos;
  final Future<Map<String, Object?>?> Function(WatchTarget)? _readHeartbeat;
  final Future<AwsCredentials?> Function(String? url)? _consoleAws;

  String get registryPath => p.join(home, 'registry.yaml');
  String get dir => p.join(home, 'watch');
  String get statePath => p.join(dir, 'state.json');
  String get incidentsPath => p.join(dir, 'incidents.jsonl');
  String get logPath => p.join(home, 'log', 'watch.log');

  Registry readRegistry() {
    final f = File(registryPath);
    return Registry.parse(f.existsSync() ? f.readAsStringSync() : '');
  }

  String get copyPath => p.join(dir, 'settings.json');

  /// The `watch:` section of the registry. The watch keeps a copy of it: a
  /// podship older than the watch (a deploy that was running during the
  /// upgrade) rewrites the registry without the section, and the watch must
  /// not go blind. A registry with the section always wins, so
  /// `watch uninstall` works.
  WatchSettings loadWatch() {
    final reg = readRegistry();
    if (reg.hasWatch) {
      final text = jsonEncode(reg.watch.toMap());
      try {
        final f = File(copyPath);
        if (!f.existsSync() || f.readAsStringSync() != text) {
          f.parent.createSync(recursive: true);
          File('$copyPath.tmp')
            ..writeAsStringSync(text)
            ..renameSync(copyPath);
        }
      } catch (_) {}
      return reg.watch;
    }
    final f = File(copyPath);
    if (!f.existsSync()) return reg.watch;
    try {
      final w = WatchSettings.fromMap(jsonDecode(f.readAsStringSync()) as Map);
      log(
        'the registry has no watch: section (an older podship wrote it); '
        'using the copy. Run podship watch install again.',
      );
      return w;
    } catch (_) {
      return reg.watch;
    }
  }

  WatchState loadState() {
    final f = File(statePath);
    if (!f.existsSync()) return WatchState();
    try {
      return WatchState.fromJson(jsonDecode(f.readAsStringSync()) as Map);
    } catch (_) {
      return WatchState();
    }
  }

  void saveState(WatchState s) {
    final f = File(statePath)..parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(s.toJson())}\n',
      );
    tmp.renameSync(f.path);
  }

  void log(String message) {
    final line = '${clock().toIso8601String()} $message';
    echo?.call(line);
    try {
      File(logPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  void _record(IncidentEvent e, List<IncidentEvent> into) {
    into.add(e);
    try {
      File(incidentsPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '${jsonEncode(e.toJson())}\n',
          mode: FileMode.append,
        );
    } catch (_) {}
  }

  /// One run. Returns null when another run holds the lock. Never throws.
  Future<WatchRun?> run() async {
    Directory(dir).createSync(recursive: true);
    final lockFile = File(
      p.join(dir, 'watch.lock'),
    ).openSync(mode: FileMode.append);
    try {
      lockFile.lockSync(FileLock.exclusive);
    } on FileSystemException {
      lockFile.closeSync();
      log('another watch run is busy; skipped');
      return null;
    }
    try {
      return await _run();
    } catch (e, st) {
      log('watch failed: $e\n$st');
      return null;
    } finally {
      try {
        lockFile.unlockSync();
      } catch (_) {}
      lockFile.closeSync();
    }
  }

  Future<WatchRun> _run() async {
    final w = loadWatch();
    final machine = _machine ?? w.machine ?? Platform.localHostname;
    writeHeartbeat(machine: machine, interval: w.interval);
    final targets = w.targets.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final events = <IncidentEvent>[];
    final sent = <Notification>[];
    if (targets.isEmpty) {
      return WatchRun(
        outcomes: const {},
        decisions: const {},
        events: events,
        notifications: sent,
      );
    }
    final rules = IncidentRules(
      alertAfter: w.alertAfter,
      healAttempts: w.healAttempts,
      healBackoff: Duration(seconds: w.healBackoff),
    );
    // Built at the first message: the secret store is read only then.
    Notifier? built;
    Future<Notifier> notify() async =>
        built ??= notifier ?? await _defaultNotifier(w);

    // 1. Every check of every target, at the same time.
    final problems = <String, String?>{};
    await Future.wait([
      for (final t in targets)
        () async {
          final ps = await Future.wait(t.checks.map(_check));
          final bad = ps.whereType<String>().toList();
          problems[t.key] = t.checks.isEmpty
              ? 'no checks'
              : bad.isEmpty
              ? null
              : bad.join('; ');
        }(),
    ]);
    final failing = [
      for (final t in targets)
        if (problems[t.key] != null) t.key,
    ];
    var online = true;
    if (failing.isNotEmpty) online = await _online();
    final outcomes = <String, Outcome>{
      for (final t in targets)
        t.key: problems[t.key] == null
            ? Outcome.pass
            : online
            ? Outcome.fail
            : Outcome.unknown,
    };
    if (!online) {
      log(
        'this machine reaches no internet: the failures of ${failing.join(', ')} do not count',
      );
    }

    // 2. The state machine.
    final state = loadState();
    final now = clock();
    state.lastRun = now;
    final decisions = <String, Decision>{};
    final ownerAlive = <String, String>{};
    for (final t in targets) {
      final s = state.targets.putIfAbsent(t.key, TargetState.new);
      var mayAlert = true;
      if (!t.owner &&
          t.heartbeatHost != null &&
          outcomes[t.key] == Outcome.fail &&
          s.incident == null &&
          s.fails + 1 >= rules.alertAfter) {
        final hb = await _heartbeat(t);
        final why = heartbeatStale(hb, now, interval: w.interval);
        if (why == null) {
          mayAlert = false;
          ownerAlive[t.key] =
              '${t.machine} is alive (heartbeat ${now.difference(DateTime.parse('${hb!['time']}')).inSeconds} s old): it alerts';
        } else {
          log('${t.key}: ${t.machine} $why: this machine alerts');
        }
      }
      decisions[t.key] = step(
        s,
        outcomes[t.key]!,
        now,
        key: t.key,
        canHeal: t.heals,
        rules: rules,
        problem: problems[t.key],
        mayAlert: mayAlert,
      );
    }
    state.targets.removeWhere((k, _) => !w.targets.containsKey(k));
    saveState(state);
    for (final e in ownerAlive.entries) {
      log('${e.key}: no alert from here: ${e.value}');
    }
    log(
      'checked ${targets.length}: ${[for (final t in targets) '${t.key} ${outcomes[t.key]!.name}${state.targets[t.key]!.fails > 0 ? ' (${state.targets[t.key]!.fails})' : ''}'].join(', ')}',
    );

    // 3. The "down" alert first, then the heal.
    final downs = [
      for (final t in targets)
        if (decisions[t.key]!.alertDown) t,
    ];
    for (final t in downs) {
      _record(
        IncidentEvent(
          time: now,
          event: 'down',
          target: t.key,
          incident: decisions[t.key]!.incident,
          machine: machine,
          problem: problems[t.key],
        ),
        events,
      );
    }
    if (downs.isNotEmpty) {
      final n = Notification(
        event: NotifyEvent.watchDown,
        title:
            'DOWN ${downs.map((t) => t.key).join(', ')} (seen from $machine)',
        body: [
          for (final t in downs)
            '${t.key}: ${problems[t.key]}\n'
                '  failing since ${state.targets[t.key]!.firstFail!.toLocal()}; '
                '${t.heals
                    ? 'healing now on $machine (engine, then podship restart)'
                    : t.owner
                    ? 'heal is off for this environment'
                    : 'runs on ${t.machine ?? 'another machine'}, whose watch does not answer: nobody heals it from here'}',
        ].join('\n'),
        ok: false,
        project: downs.length == 1 ? downs.first.project : null,
        env: downs.length == 1 ? downs.first.env : null,
        host: machine,
        data: {
          'targets': [for (final t in downs) t.key],
          'machine': machine,
        },
      );
      sent.add(n);
      await _send(await notify(), n);
    }

    final toHeal = [
      for (final t in targets)
        if (decisions[t.key]!.heal) t,
    ];
    if (toHeal.isNotEmpty) {
      // The other machines read the heartbeat: a heal may take minutes, and
      // they must not alert for this machine meanwhile.
      writeHeartbeat(
        machine: machine,
        interval: w.interval,
        busyUntil: clock().add(const Duration(minutes: 20)),
      );
      await _heal(toHeal, decisions, problems, machine, events);
      writeHeartbeat(machine: machine, interval: w.interval);
    }

    // 4. Heals used up, still failing: once per incident.
    final still = [
      for (final t in targets)
        if (decisions[t.key]!.alertStillDown) t,
    ];
    for (final t in still) {
      _record(
        IncidentEvent(
          time: now,
          event: 'still_down',
          target: t.key,
          incident: decisions[t.key]!.incident,
          machine: machine,
          problem: problems[t.key],
          attempt: state.targets[t.key]!.heals,
        ),
        events,
      );
    }
    if (still.isNotEmpty) {
      final n = Notification(
        event: NotifyEvent.watchDown,
        title:
            'STILL DOWN ${still.map((t) => t.key).join(', ')} after ${rules.healAttempts} heal attempts (on $machine)',
        body: [
          for (final t in still)
            '${t.key}: ${problems[t.key]}; down for ${formatDuration(now.difference(state.targets[t.key]!.firstFail!))}. The watch stops healing; a person must look.',
        ].join('\n'),
        ok: false,
        host: machine,
        data: {
          'targets': [for (final t in still) t.key],
        },
      );
      sent.add(n);
      await _send(await notify(), n);
    }

    // 5. Recovered: once per incident, with the downtime.
    final ups = [
      for (final t in targets)
        if (decisions[t.key]!.alertRecovered) t,
    ];
    for (final t in ups) {
      _record(
        IncidentEvent(
          time: now,
          event: 'recovered',
          target: t.key,
          incident: decisions[t.key]!.incident,
          machine: machine,
          downtime: decisions[t.key]!.downtime,
        ),
        events,
      );
    }
    if (ups.isNotEmpty) {
      final n = Notification(
        event: NotifyEvent.watchRecovered,
        title:
            'RECOVERED ${ups.map((t) => t.key).join(', ')} (seen from $machine)',
        body: [
          for (final t in ups)
            '${t.key}: up again after ${formatDuration(decisions[t.key]!.downtime ?? Duration.zero)} of downtime',
        ].join('\n'),
        ok: true,
        project: ups.length == 1 ? ups.first.project : null,
        env: ups.length == 1 ? ups.first.env : null,
        host: machine,
        duration: ups.length == 1 ? decisions[ups.first.key]!.downtime : null,
        data: {
          'targets': [for (final t in ups) t.key],
          'downtime_s': {
            for (final t in ups) t.key: decisions[t.key]!.downtime?.inSeconds,
          },
        },
      );
      sent.add(n);
      await _send(await notify(), n);
    }
    return WatchRun(
      outcomes: outcomes,
      decisions: decisions,
      events: events,
      notifications: sent,
      online: online,
    );
  }

  Future<void> _send(Notifier notify, Notification n) async {
    log('alert: ${n.title}');
    await notify.send(
      n,
      log: Log((e) {
        if (e is LogLine) log(e.text);
      }),
    );
  }

  Future<Notifier> _defaultNotifier(WatchSettings w) async {
    final cfg = watchNotifyConfig(w);
    final email = cfg.channels.any((c) => c.kind == 'email');
    SesApi Function(String)? ses;
    if (email) {
      final creds = await awsFromConsole(w.consoleUrl);
      if (creds == null) {
        log(
          'no AWS credential from the console${w.consoleUrl == null ? ' (watch.console is not set)' : ''}: '
          'email alerts are off; macOS notifications only',
        );
      } else {
        ses = (region) => SesApi(creds, region: region);
      }
    }
    return Notifier(cfg, ses: ses);
  }

  /// The AWS credential of the workspace's AWS integration in the podship
  /// console at [url], with this machine's `podship login` token:
  /// `GET <console>/podship/v1/integrations/aws/credentials` answers
  /// `{"access_key_id", "secret_access_key", "session_token"}` (short-lived
  /// STS keys). Null when there is no console, no token, or the console
  /// does not offer it (yet). Never logs a value.
  Future<AwsCredentials?> awsFromConsole(String? url) async {
    if (_consoleAws != null) return _consoleAws(url);
    if (url == null) return null;
    final token = TokenStore().readStored(url);
    if (token == null || token.isEmpty) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final base = url.endsWith('/') ? url : '$url/';
      final req = await client.getUrl(
        Uri.parse('${base}podship/v1/integrations/aws/credentials'),
      );
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final j = jsonDecode(body);
      if (j is! Map || j['access_key_id'] == null) return null;
      return AwsCredentials.fromJson(jsonEncode(j));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, String> _env(WatchTarget t) => {
    'PATH': [
      ?t.path,
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/Applications/Docker.app/Contents/Resources/bin',
      Platform.environment['PATH'] ?? '/usr/bin:/bin:/usr/sbin:/sbin',
    ].join(':'),
  };

  Future<bool> _engineUp(WatchTarget t) async {
    final r = await _process(
      'docker',
      ['info', '--format', '{{.ServerVersion}}'],
      environment: _env(t),
      timeout: const Duration(seconds: 20),
    );
    return r.code == 0 && r.out.trim().isNotEmpty;
  }

  Future<Engine> _detectEngine(WatchTarget t, Engine configured) async {
    if (configured != Engine.auto) return configured;
    if ((isMacos ?? Platform.isMacOS) == false) return Engine.none;
    final r = await _process(
      'bash',
      ['-c', 'command -v colima'],
      environment: _env(t),
      timeout: const Duration(seconds: 5),
    );
    if (r.code == 0) return Engine.colima;
    if (Directory('/Applications/Docker.app').existsSync()) {
      return Engine.dockerDesktop;
    }
    return Engine.none;
  }

  Future<bool> _poll(Future<bool> Function() ok, Duration limit) async {
    final end = clock().add(limit);
    while (true) {
      if (await ok()) return true;
      if (!clock().isBefore(end)) return false;
      await Future<void>.delayed(pollEvery);
    }
  }

  Future<void> _heal(
    List<WatchTarget> targets,
    Map<String, Decision> decisions,
    Map<String, String?> problems,
    String machine,
    List<IncidentEvent> events,
  ) async {
    final w = loadWatch();
    final first = targets.first;
    // The engine first: one engine per machine.
    var engineRestarted = false;
    if (w.engine != Engine.none && !await _engineUp(first)) {
      final engine = await _detectEngine(first, w.engine);
      log('the Docker engine does not answer; starting ${engine.id}');
      String detail;
      var ok = false;
      if (engine == Engine.none) {
        detail = 'no engine to start on this machine';
      } else {
        final (exe, args) = engine == Engine.colima
            ? ('colima', ['start'])
            : ('open', ['-a', 'Docker']);
        final r = await _process(
          exe,
          args,
          environment: _env(first),
          timeout: const Duration(minutes: 5),
        );
        ok = await _poll(() => _engineUp(first), engineWait);
        engineRestarted = true;
        detail =
            '${[exe, ...args].join(' ')}: exit ${r.code}; engine ${ok ? 'answers' : 'still silent after ${engineWait.inSeconds} s'}';
      }
      log(detail);
      for (final t in targets) {
        _record(
          IncidentEvent(
            time: clock(),
            event: 'engine_start',
            target: t.key,
            incident: decisions[t.key]!.incident,
            machine: machine,
            ok: ok,
            detail: detail,
          ),
          events,
        );
      }
    }
    for (final t in targets) {
      final attempt = decisions[t.key]!.healAttempt;
      final local = t.localUrls;
      Future<bool> localUp() async {
        for (final u in local) {
          if (await _localOk(u)) return true;
        }
        return false;
      }

      if (local.isNotEmpty) {
        // After an engine start the containers come back by themselves
        // (restart: unless-stopped); give them a moment first.
        final up = engineRestarted
            ? await _poll(localUp, localWait)
            : await localUp();
        if (up) {
          final detail = engineRestarted
              ? 'healthy on this machine after the engine start: no restart'
              : 'healthy on this machine (${local.first}); the public route fails: '
                    'look at the tunnel or DNS. No restart.';
          log('${t.key}: $detail');
          _record(
            IncidentEvent(
              time: clock(),
              event: 'heal',
              target: t.key,
              incident: decisions[t.key]!.incident,
              machine: machine,
              attempt: attempt,
              ok: engineRestarted,
              detail: detail,
            ),
            events,
          );
          continue;
        }
      }
      // podship's own restart of the current release, never a deploy, and
      // only of the failing app services: the database only when it fails.
      final ps = await _services(t);
      final services = servicesToHeal(ps, serverService: t.serverService);
      final (exe, pre) = podshipCommand();
      final args = [
        ...pre,
        '-C',
        t.releaseDir!,
        '--yes',
        '--no-notify',
        'restart',
        '--env',
        t.env,
        ...services,
      ];
      log(
        '${t.key}: heal attempt $attempt: podship restart --env ${t.env} ${services.join(' ')}',
      );
      final r = await _process(
        exe,
        args,
        environment: {
          ..._env(t),
          'PODSHIP_LOCAL_ENV': t.env,
          'PODSHIP_ACTOR': 'podship-watch',
        },
        cwd: t.releaseDir,
        timeout: const Duration(minutes: 10),
      );
      final tail = const LineSplitter()
          .convert(r.out)
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final detail =
          'podship restart --env ${t.env} ${services.join(' ')}: exit ${r.code}'
          '${tail.isEmpty ? '' : ': ${tail.skip(tail.length > 3 ? tail.length - 3 : 0).join(' | ')}'}';
      log('${t.key}: $detail');
      _record(
        IncidentEvent(
          time: clock(),
          event: 'heal',
          target: t.key,
          incident: decisions[t.key]!.incident,
          machine: machine,
          attempt: attempt,
          ok: r.code == 0,
          detail: detail,
        ),
        events,
      );
    }
  }

  String get heartbeatPath => p.join(dir, 'heartbeat.json');

  /// `<home>/watch/heartbeat.json`: this machine's watch is alive. The other
  /// machines read it over ssh before they alert for an environment of this
  /// machine.
  void writeHeartbeat({
    required String machine,
    required int interval,
    DateTime? busyUntil,
  }) {
    try {
      Directory(dir).createSync(recursive: true);
      File('$heartbeatPath.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'machine': machine,
            'time': clock().toUtc().toIso8601String(),
            'interval': interval,
            'busy_until': ?busyUntil?.toUtc().toIso8601String(),
          }),
        )
        ..renameSync(heartbeatPath);
    } catch (_) {}
  }

  Future<Map<String, Object?>?> _heartbeat(WatchTarget t) async {
    if (_readHeartbeat != null) return _readHeartbeat(t);
    final r = await _process('ssh', [
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=8',
      t.heartbeatHost!,
      'cat',
      t.heartbeatPath!,
    ], timeout: const Duration(seconds: 20));
    if (r.code != 0) return null;
    try {
      final j = jsonDecode(r.out.trim());
      return j is Map ? j.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// The services of [t]'s current release, from `compose ps`.
  Future<List<ComposeService>?> _services(WatchTarget t) async {
    final r = await _process(
      'bash',
      [
        p.posix.join(t.releaseDir!, '.podship', 'compose.sh'),
        'ps',
        '-a',
        '--format',
        'json',
      ],
      environment: _env(t),
      cwd: t.releaseDir,
      timeout: const Duration(seconds: 30),
    );
    if (r.code != 0) return null;
    return parseComposePs(r.out);
  }

  /// The last [n] incident events of this machine, oldest first.
  List<IncidentEvent> history({int n = 50, String? target}) {
    final f = File(incidentsPath);
    if (!f.existsSync()) return const [];
    final all = <IncidentEvent>[];
    for (final l in f.readAsLinesSync()) {
      if (l.trim().isEmpty) continue;
      try {
        final e = IncidentEvent.fromJson(jsonDecode(l) as Map);
        if (target == null || e.target == target) all.add(e);
      } catch (_) {}
    }
    return all.length > n ? all.sublist(all.length - n) : all;
  }
}
