// task list|run|sync|history: the recurring tasks of an environment
// (`tasks:` in podship.yaml), run in the server container of the current
// release by the machine's scheduler.

import 'dart:io';

import 'package:args/command_runner.dart';

import '../ops/task_ops.dart' show formatTaskRow;
import 'base.dart';

/// `--plan` on a task command: the same as `--dry-run` (prints the plan,
/// changes nothing, runs nothing).
mixin _PlanFlag on PodshipCommand {
  void addPlanFlag() => argParser.addFlag(
    'plan',
    negatable: false,
    help: 'Print the plan and change nothing (the same as --dry-run).',
  );

  @override
  bool get dryRun => super.dryRun || argResults?['plan'] == true;
}

class TaskListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'The tasks of an environment: schedule, last run, next run, and whether the server has them.';
  @override
  Future<int> execute() async {
    final rows = await api.tasks(env.name);
    if (json) {
      printJson(rows);
      return 0;
    }
    if (rows.isEmpty) {
      stdout.writeln('no tasks in environments.${env.name}.tasks');
    }
    for (final r in rows) {
      stdout.writeln(formatTaskRow(r));
    }
    return 0;
  }
}

class TaskRunCommand extends PodshipCommand with _PlanFlag {
  TaskRunCommand() {
    addPlanFlag();
  }
  @override
  String get name => 'run';
  @override
  String get description =>
      'Run a task now, on its server, in a container of the current release. '
      'Never runs twice at once; --plan prints what would run.';
  @override
  String get invocation => '$exe task run <name> --env <env> [--plan]';
  @override
  bool get mutating => true;

  /// A task can reset data: staging by default, production must be named.
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('pass a task name (podship task list)', usage);
    }
    return runOp(api.taskRun(env.name, argResults!.rest.first));
  }
}

class TaskSyncCommand extends PodshipCommand with _PlanFlag {
  TaskSyncCommand() {
    addPlanFlag();
  }
  @override
  String get name => 'sync';
  @override
  String get description =>
      'Write the tasks of podship.yaml into the server\'s registry without a deploy (a deploy does it too).';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() => runOp(api.taskSync(env.name));
}

class TaskHistoryCommand extends PodshipCommand {
  TaskHistoryCommand() {
    argParser
      ..addOption('limit', defaultsTo: '20')
      ..addOption('task', help: 'Only this task.');
  }
  @override
  String get name => 'history';
  @override
  String get description =>
      'The runs of the tasks, scheduled and manual: when, who, the release, the outcome.';
  @override
  Future<int> execute() async {
    final list = await api.taskHistory(
      env.name,
      task: argResults!['task'] as String?,
      limit: int.parse(argResults!['limit'] as String),
    );
    if (json) {
      printJson([for (final r in list) r.toJson()]);
      return 0;
    }
    if (list.isEmpty) stdout.writeln('no task runs yet');
    for (final r in list) {
      final j = r.json;
      stdout.writeln(
        [
          r.startedAt.split('.').first,
          r.operation.padRight(20),
          r.ok ? 'ok    ' : 'FAILED',
          '${((j['duration_ms'] as num? ?? 0) / 1000).toStringAsFixed(1)} s'
              .padLeft(8),
          ?r.release,
          '${j['actor'] ?? ''}',
          if (!r.ok) '${j['error'] ?? ''}',
          if (r.logPath != null) r.logPath!,
        ].join('  '),
      );
    }
    return 0;
  }
}

/// The task commands as a group.
Command<int> taskGroup() => GroupCommand(
  'task',
  'Recurring tasks of an environment (tasks: in podship.yaml): list, run now, sync to the server, history.',
  [
    TaskListCommand(),
    TaskRunCommand(),
    TaskSyncCommand(),
    TaskHistoryCommand(),
  ],
);
