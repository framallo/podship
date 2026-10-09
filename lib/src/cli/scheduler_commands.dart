// scheduler install|status|list|run-once|tick|uninstall.
//
// Without --env, the commands address this machine (the off-site pulls);
// with --env, the server of that environment. `tick` and `run-once --home`
// are what the agent itself runs on a machine.

import 'dart:io';

import 'package:args/command_runner.dart';

import '../ops/context.dart';
import '../scheduler/scheduler.dart';
import '../watch/runner.dart';
import 'backup_commands.dart' show formatJob;
import 'base.dart';

abstract class _SchedulerCommand extends PodshipCommand {
  _SchedulerCommand() {
    argParser.addOption(
      'env',
      abbr: 'e',
      help:
          'The environment whose server runs the scheduler (default: this machine).',
    );
  }

  @override
  bool get takesEnv => false;

  /// `--env`, or null for this machine.
  String? get envName => argResults!['env'] as String?;
}

class SchedulerInstallCommand extends _SchedulerCommand {
  SchedulerInstallCommand() {
    argParser
      ..addOption(
        'at',
        help:
            'The time of the nightly run, HH:MM in the machine\'s local time (default: the registry\'s, or 03:00).',
      )
      ..addOption(
        'binary',
        help:
            'A compiled podship to put on the machine (default: this one, or a fresh dart compile exe).',
      );
  }
  @override
  String get name => 'install';
  @override
  String get description =>
      'Register the single podship scheduler agent of a machine (launchd on macOS, systemd on Linux), once. '
      'Imports the per-environment backup and pull agents podship used to install and retires them. Idempotent.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() => runOp(
    api.schedulerInstall(
      envName: envName,
      at: argResults!['at'] as String?,
      binary: argResults!['binary'] as String?,
    ),
  );
}

class SchedulerUninstallCommand extends _SchedulerCommand {
  @override
  String get name => 'uninstall';
  @override
  String get description =>
      'Remove the scheduler agent of a machine. The registry and its jobs stay.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() => runOp(api.schedulerUninstall(envName: envName));
}

class SchedulerStatusCommand extends _SchedulerCommand {
  @override
  String get name => 'status';
  @override
  String get description =>
      'The scheduler of a machine: agent, nightly run time, jobs with their last run, log tail.';
  @override
  Future<int> execute() async {
    final st = await api.schedulerStatusOf(envName: envName);
    if (json) {
      printJson(st.toJson());
      return 0;
    }
    final t = api.schedulerTarget(envName);
    stdout.writeln(
      'scheduler on ${t.label} (${t.home}): '
      '${st.agentLoaded ? 'agent installed' : 'agent NOT installed'}'
      '${st.agentAt != null && st.agentAt != st.registry.scheduler.at ? ' at ${st.agentAt} (registry says ${st.registry.scheduler.at}: run scheduler install)' : ', nightly at ${st.registry.scheduler.at}'}'
      '${st.binVersion == null ? '' : ', ${st.binVersion}'}',
    );
    stdout.writeln(
      'last run: ${st.state['last_tick'] ?? 'never'}; ${st.jobs.length} job(s)',
    );
    for (final j in st.jobs) {
      stdout.writeln('  ${formatJob(j)}');
    }
    if (st.logTail.isNotEmpty) {
      stdout.writeln('log (${t.home}/log/scheduler.log):');
      for (final l in st.logTail) {
        stdout.writeln('  $l');
      }
    }
    return 0;
  }
}

class SchedulerListCommand extends _SchedulerCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'The scheduled jobs of a machine with their last run (list_schedules).';
  @override
  Future<int> execute() async {
    final jobs = await api.schedules(envName: envName);
    if (json) {
      printJson(jobs);
      return 0;
    }
    if (jobs.isEmpty) stdout.writeln('no jobs');
    for (final j in jobs) {
      stdout.writeln(formatJob(j));
    }
    return 0;
  }
}

class SchedulerRunOnceCommand extends _SchedulerCommand {
  SchedulerRunOnceCommand() {
    argParser.addOption(
      'home',
      help:
          'Run the job of this machine\'s registry in this process (what the agent uses over ssh).',
      hide: true,
    );
  }
  @override
  String get name => 'run-once';
  @override
  String get description =>
      'Run one job now on the machine that holds it (run_job). Jobs: scheduler list.';
  @override
  String get invocation => '$exe scheduler run-once <job id> [--env <env>]';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('pass a job id, like backup:shop/production', usage);
    }
    final id = argResults!.rest.first;
    final home = argResults!['home'] as String?;
    if (home != null) {
      final runner = JobRunner(home, echo: stdout.writeln);
      final job = runner.readRegistry().jobs[id];
      if (job == null) throw Aborted('no job "$id" in $home/registry.yaml');
      final run = await runner.runJob(job);
      return run.ok ? 0 : 1;
    }
    return runOp(api.schedulerRun(id, envName: envName));
  }
}

/// What the agent runs: `podship scheduler tick --home <home>`.
class SchedulerTickCommand extends PodshipCommand {
  SchedulerTickCommand() {
    argParser
      ..addOption(
        'home',
        help: 'The podship home of this machine (its registry.yaml).',
        mandatory: true,
      )
      ..addFlag(
        'seed',
        negatable: false,
        help:
            'Mark jobs without state as run today and run nothing (the install does this).',
      )
      ..addFlag('force', negatable: false, help: 'Run every job, due or not.')
      ..addFlag(
        'nightly',
        negatable: false,
        help:
            'Run only the nightly jobs, here (the tick starts this in the background).',
      )
      ..addFlag(
        'no-watch',
        negatable: false,
        help: 'Skip the watch in this tick.',
      );
  }
  @override
  String get name => 'tick';
  @override
  String get description =>
      'One run of the agent on this machine: the watch (every few minutes), then every nightly job that did not run today (backups, then pulls). The agent calls it.';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    final home = argResults!['home'] as String;
    final runner = JobRunner(home, echo: stdout.writeln);
    if (argResults!['seed'] == true) {
      final seeded = runner.seed();
      stdout.writeln(
        seeded.isEmpty
            ? 'nothing to seed'
            : 'seeded ${seeded.length} job(s): first run tonight',
      );
      return 0;
    }
    final force = argResults!['force'] == true;
    if (argResults!['nightly'] == true || force) {
      final runs = await runner.tick(force: force);
      // The agent must stay alive whatever a job did.
      return runs.any((r) => !r.ok && !r.skipped) ? 1 : 0;
    }
    final watched = runner.readRegistry().watch.targets.isNotEmpty;
    if (watched && argResults!['no-watch'] != true) {
      await WatchRunner(home, echo: stdout.writeln).run();
    }
    if (!watched) {
      // No watch on this machine: the nightly jobs run here, as before.
      final runs = await runner.tick();
      return runs.any((r) => !r.ok && !r.skipped) ? 1 : 0;
    }
    if (runner.nightlyDue()) {
      // A backup may take minutes, and launchd does not start the next tick
      // while this one runs: the nightly jobs go to their own process (their
      // own lock), so the watch keeps its pace.
      final (exe, pre) = podshipCommand();
      await Process.start(exe, [
        ...pre,
        'scheduler',
        'tick',
        '--home',
        home,
        '--nightly',
      ], mode: ProcessStartMode.detached);
      runner.log('tick: nightly jobs started in the background');
    }
    return 0;
  }
}

/// The scheduler commands as a group.
Command<int> schedulerGroup() => GroupCommand(
  'scheduler',
  'The nightly scheduler agent of a machine (one per machine): install, status, run a job, remove.',
  [
    SchedulerInstallCommand(),
    SchedulerStatusCommand(),
    SchedulerListCommand(),
    SchedulerRunOnceCommand(),
    SchedulerTickCommand(),
    SchedulerUninstallCommand(),
  ],
);
