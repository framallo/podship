// Shared command plumbing: global flags, --env, config loading.

import 'dart:async';

import 'package:args/command_runner.dart';

import '../config/config.dart';
import '../ops/context.dart';
import '../ops/resolve.dart';
import '../ops/state.dart';
import '../remote/ssh.dart';
import '../util/log.dart';

/// The executable name shown in help.
const exe = 'podship';

abstract class PodshipCommand extends Command<int> {
  PodshipCommand() {
    addCommonFlags();
  }

  /// Whether the command changes something. Mutating commands get
  /// `--dry-run`.
  bool get mutating => false;

  /// Whether the command can destroy data or stop production. Those default
  /// to `--env staging` and need `--env production` spelled out.
  bool get destructive => false;

  /// Whether the command takes `--env`.
  bool get takesEnv => true;

  bool _flagsAdded = false;

  void addCommonFlags() {
    if (_flagsAdded) return;
    _flagsAdded = true;
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

  late final Log log = Log(
    verbose: globalResults?['verbose'] == true,
    quiet: globalResults?['quiet'] == true,
  );

  bool get dryRun => mutating && argResults?['dry-run'] == true;
  bool get yes => globalResults?['yes'] == true;

  PodshipConfig? _config;
  PodshipConfig get config =>
      _config ??= PodshipConfig.load(globalResults?['project-dir'] as String?);

  Ssh get ssh => Ssh(
    extraOptions: [
      if (globalResults?['ssh-key'] case final String k) ...[
        '-i',
        k,
        '-o',
        'IdentitiesOnly=yes',
      ],
    ],
    verbose: log.verbose,
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

  /// For destructive commands: production must be named, and confirmed.
  EnvConfig get guardedEnv {
    final e = env;
    final named = argResults?['env'] as String?;
    if (e.isProduction && named != 'production') {
      throw UsageException('production must be named: --env production', usage);
    }
    return e;
  }

  /// Fetches the state and resolves the environment against the registry.
  Future<({EnvState state, ResolvedEnv r})> load(EnvConfig e) async {
    final state = await fetchState(ctx, e);
    final r = resolveEnv(
      config,
      e,
      state.registry,
      listening: state.listening,
      now: DateTime.now().toUtc().toIso8601String(),
    );
    return (state: state, r: r);
  }

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
    } on RemoteException catch (e) {
      log.error('$e');
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
