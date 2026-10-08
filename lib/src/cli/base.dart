// Shared command plumbing: global flags, --env, rendering of events.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/events.dart';
import '../api/podship.dart';
import '../api/render.dart';
import '../protocol/protocol.dart';
import '../protocol/tokens.dart';
import '../protocol/transport.dart';
import '../config/config.dart';
import '../ops/app_ops.dart' show Integrations;
import '../ops/context.dart';
import '../plan/plan.dart';
import '../remote/ssh.dart';
import '../server/registry.dart';
import '../util/log.dart';

/// The executable name shown in help.
const exe = 'podship';

abstract class PodshipCommand extends Command<int> {
  PodshipCommand() {
    if (takesEnv) {
      argParser.addOption(
        'env',
        abbr: 'e',
        help: destructive
            ? 'The environment. Defaults to staging; production must be named.'
            : 'The environment (default: staging, or the only one).',
      );
    }
    if (mutating) {
      argParser.addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the plan and change nothing.',
      );
    }
  }

  /// Whether the command changes something. Mutating commands get
  /// `--dry-run`.
  bool get mutating => false;

  /// Whether the command can destroy data or stop production. Those default
  /// to `--env staging` and need `--env production` spelled out.
  bool get destructive => false;

  /// Whether the command takes `--env`.
  bool get takesEnv => true;

  bool get verbose => globalResults?['verbose'] == true;
  bool get quiet => globalResults?['quiet'] == true;
  bool get json => globalResults?['json'] == true;
  bool get dryRun => mutating && argResults?['dry-run'] == true;
  bool get yes => globalResults?['yes'] == true;

  bool get _color => !json && stdout.hasTerminal && stdout.supportsAnsiEscapes;

  /// Prints one event: a JSON line with `--json`, else text.
  void render(PodshipEvent e) {
    if (json) {
      stdout.writeln(jsonEncode(e.toJson()));
      return;
    }
    if (e is PlanReady) {
      if (dryRun) stdout.write(e.text);
      return;
    }
    if (quiet &&
        e is! OperationFinished &&
        !(e is LogLine && e.level == LogLevel.error)) {
      return;
    }
    final text = renderEventText(e, verbose: verbose, color: _color);
    if (text == null) return;
    final err =
        (e is LogLine &&
            (e.level == LogLevel.error || e.level == LogLevel.warn)) ||
        e is StepFailed ||
        (e is OperationFinished && !e.result.ok);
    (err ? stderr : stdout).writeln(text);
  }

  late final Log log = Log(render, verbose: verbose, quiet: quiet);

  PodshipConfig? _config;
  PodshipConfig get config =>
      _config ??= PodshipConfig.load(globalResults?['project-dir'] as String?);

  /// The config, or an empty one outside a project (for server commands).
  PodshipConfig get configOrEmpty {
    try {
      return config;
    } on ConfigException {
      return _config = PodshipConfig(
        project: 'podship',
        serverPackage: '',
        build: BuildConfig(),
        compose: ComposeConfig(),
        environments: const {},
      );
    }
  }

  List<String> get sshOptions => [
    if (globalResults?['ssh-key'] case final String k) ...[
      '-i',
      k,
      '-o',
      'IdentitiesOnly=yes',
    ],
  ];

  Ssh get ssh => Ssh(extraOptions: sshOptions, verbose: verbose);

  /// `--notify` / `--no-notify`, or null when neither was given.
  bool? get notifyFlag => globalResults?.wasParsed('notify') == true
      ? globalResults!['notify'] as bool
      : null;

  /// The notifier of this command: the project's `notify:` (and the global
  /// one), turned off by `--no-notify`, turned on by `--notify` even when
  /// the config says `enabled: false`.
  late final Notifier notifier = _buildNotifier();

  Notifier _buildNotifier() {
    final flag = notifyFlag;
    final cfg = flag == true
        ? NotifyConfig(
            events: config.notify.events,
            channels: config.notify.channels,
            bell: config.notify.bell,
          )
        : config.notify;
    // The secret store (Keychain) is read only when an email channel
    // exists, so plain commands do not pay for it.
    final email = cfg.channels.any((c) => c.kind == 'email');
    final integrations = email ? Integrations() : null;
    return Notifier(
      cfg,
      enabled: flag ?? true,
      ses: integrations != null && integrations.hasAws
          ? integrations.ses
          : null,
    );
  }

  /// The library, configured from the global flags.
  Podship get api => Podship(
    config,
    sshOptions: sshOptions,
    dryRun: dryRun,
    verbose: verbose,
    notifier: notifier,
  );

  Ctx get ctx =>
      Ctx(config: config, ssh: ssh, log: log, dryRun: dryRun, yes: yes);

  /// The environment named by `--env`.
  EnvConfig get env {
    final name = argResults?['env'] as String?;
    if (name != null) return config.env(name);
    final envs = config.environments;
    if (envs.length == 1) return envs.values.first;
    if (envs.containsKey('staging')) return envs['staging']!;
    throw UsageException('pass --env (${envs.keys.join(', ')})', usage);
  }

  /// For destructive commands: production must be named.
  EnvConfig get guardedEnv {
    final e = env;
    if (e.isProduction && argResults?['env'] != 'production') {
      throw UsageException('production must be named: --env production', usage);
    }
    return e;
  }

  /// Asks the user to type the environment name [name]. [typed] is the
  /// value of `--confirm` for CI.
  void confirmEnvName(String name, String what, String? typed) {
    if (dryRun) return;
    if (typed != null) {
      if (typed != name) throw Aborted('--confirm must be "$name"');
      return;
    }
    if (!stdin.hasTerminal) {
      throw Aborted(
        '$what Pass --confirm $name to confirm without a terminal.',
      );
    }
    stdout.write('$what\nType "$name" to continue: ');
    if (stdin.readLineSync(encoding: utf8)?.trim() != name) {
      throw Aborted('cancelled');
    }
  }

  /// `ssh` or `console`: `--via`, else the environment's or the project's
  /// `transport`.
  String get via {
    final flag = globalResults?['via'] as String?;
    if (flag != null) return flag;
    try {
      config;
    } on ConfigException {
      return 'ssh';
    }
    final name = takesEnv ? (argResults?['env'] as String?) : null;
    final e = name == null ? null : config.environments[name];
    return e?.transport ?? config.transport;
  }

  /// The console URL: `PODSHIP_CONSOLE_URL`, else `console.url`.
  String get consoleUrl {
    final u = Platform.environment['PODSHIP_CONSOLE_URL'] ?? config.consoleUrl;
    if (u == null) {
      throw Aborted(
        'no console: set console.url in podship.yaml or PODSHIP_CONSOLE_URL',
      );
    }
    return u;
  }

  ConsoleTransport get console {
    final url = consoleUrl;
    final token = TokenStore().read(url);
    if (token == null) {
      throw Aborted('not signed in to $url: run `podship login $url`');
    }
    return ConsoleTransport(url, token);
  }

  /// Renders the events of [op] and returns 0 when it worked. With the
  /// console transport, sends [op]'s request to the console instead and
  /// renders the console's events the same way.
  Future<int> runOp(Operation op) async {
    if (via == 'console') return runRemote(op.request);
    final watcher = OperationWatcher();
    await op.events.forEach((e) {
      watcher.onEvent(e);
      render(e);
    });
    final r = await op.result;
    finish(r, watcher.stages);
    return r.ok ? 0 : 1;
  }

  /// A command that took this long gets a bell and a summary line.
  static const longCommand = Duration(seconds: 20);

  /// After a long command: a terminal bell (unless `notify.bell: false` or
  /// `--no-notify`) and one line with the outcome, the release, the time
  /// and the slowest stages.
  void finish(OperationResult r, List<StageTiming> stages) {
    if (json || r.dryRun || r.duration < longCommand) return;
    final bell =
        notifyFlag != false && config.notify.bell && stdout.hasTerminal;
    final line = summaryLine(r, stages);
    (r.ok ? stdout : stderr).writeln('${bell ? '\x07' : ''}$line');
  }

  /// Runs [req] on the console and renders its events.
  Future<int> runRemote(OperationRequest req) async {
    try {
      var ok = false;
      await for (final j in console.run(req)) {
        final e = eventFromJson(j);
        if (e is OperationFinished) ok = e.result.ok;
        render(e);
      }
      return ok ? 0 : 1;
    } on ConsoleUnreachable catch (e) {
      log.error('$e');
      log.info(
        'If your ssh key has access to the server, run the same command with --via ssh.',
      );
      return 1;
    } on ConsoleRefused catch (e) {
      log.error('$e');
      return e.status == 401 || e.status == 403 ? 3 : 1;
    }
  }

  /// For read commands: the console request that returns the same data.
  OperationRequest? get consoleRead => null;

  /// A request for [operation] on the `--env` environment.
  OperationRequest request(
    String operation, [
    Map<String, Object?> params = const {},
  ]) => OperationRequest(
    operation: operation,
    project: config.project,
    env: env.name,
    params: params,
  );

  /// Prints [value] as indented JSON.
  void printJson(Object? value) =>
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));

  @override
  FutureOr<int> run() async {
    try {
      final read = via == 'console' ? consoleRead : null;
      if (read != null) {
        var code = 1;
        Object? value;
        final rc = await runRemoteRead(read, (v) => value = v);
        code = rc;
        if (code == 0) printJson(value);
        return code;
      }
      return await execute();
    } on Aborted catch (e) {
      log.error(e.message);
      return 2;
    } on ConfigException catch (e) {
      log.error('$e');
      return 2;
    } on RegistryConflict catch (e) {
      log.error('$e');
      return 2;
    } on RemoteException catch (e) {
      log.error('$e');
      return 1;
    } on StepError catch (e) {
      log.error('failed: $e');
      return 1;
    }
  }

  Future<int> execute();

  Future<int> runRemoteRead(
    OperationRequest req,
    void Function(Object?) onValue,
  ) async {
    try {
      await for (final j in console.run(req)) {
        final e = eventFromJson(j);
        if (e is OperationFinished) {
          if (!e.result.ok) {
            log.error(e.result.error ?? 'failed');
            return 1;
          }
          onValue(e.result.data['value']);
          return 0;
        }
      }
      return 1;
    } on ConsoleUnreachable catch (e) {
      log.error('$e');
      log.info(
        'If your ssh key has access to the server, run the same command with --via ssh.',
      );
      return 1;
    } on ConsoleRefused catch (e) {
      log.error('$e');
      return 3;
    }
  }
}

/// A command group like `backup` or `db`.
class GroupCommand extends Command<int> {
  GroupCommand(this.name, this.description, List<Command<int>> subs) {
    for (final s in subs) {
      addSubcommand(s);
    }
  }
  @override
  final String name;
  @override
  final String description;
}

/// One line: `deploy staging ok: 20261008-015437-0314c97 in 282.7 s (build 149.6 s, tests 48.1 s)`.
String summaryLine(OperationResult r, List<StageTiming> stages) {
  String secs(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  final slow = [
    for (final s in stages)
      if (!s.recovery && s.duration.inSeconds >= 5) s,
  ]..sort((a, b) => b.duration.compareTo(a.duration));
  final stagesText = slow
      .take(3)
      .map((s) => '${shortStage(s.title)} ${secs(s.duration)}')
      .join(', ');
  return [
    r.operation,
    if (r.env != null) r.env,
    r.ok ? 'ok:' : 'FAILED:',
    if (r.release != null) r.release,
    if (!r.ok && r.error != null) r.error,
    'in ${secs(r.duration)}',
    if (stagesText.isNotEmpty) '($stagesText)',
  ].join(' ');
}
