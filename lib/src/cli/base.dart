// Shared command plumbing: global flags, --env, rendering of events.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/events.dart';
import '../api/podship.dart';
import '../api/render.dart';
import '../config/config.dart';
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

  List<String> get sshOptions => [
    if (globalResults?['ssh-key'] case final String k) ...[
      '-i',
      k,
      '-o',
      'IdentitiesOnly=yes',
    ],
  ];

  Ssh get ssh => Ssh(extraOptions: sshOptions, verbose: verbose);

  /// The library, configured from the global flags.
  Podship get api =>
      Podship(config, sshOptions: sshOptions, dryRun: dryRun, verbose: verbose);

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

  /// Renders the events of [op] and returns 0 when it worked.
  Future<int> runOp(Operation op) async {
    await op.events.forEach(render);
    final r = await op.result;
    return r.ok ? 0 : 1;
  }

  /// Prints [value] as indented JSON.
  void printJson(Object? value) =>
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));

  @override
  FutureOr<int> run() async {
    try {
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
