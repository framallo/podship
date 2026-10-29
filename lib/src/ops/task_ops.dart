// Recurring tasks (`tasks:` of an environment in podship.yaml): argv run in
// the server container of the current release, on a schedule, by the
// machine's scheduler agent.
//
// A task is a registry job of kind `command` with `task: true`, so an agent
// older than tasks still reads the registry (it runs the job at the nightly
// time and ignores `at`, `timeout` and `redact`). Each deploy, and
// `task sync`, rewrite the jobs of the environment from podship.yaml. The
// job runs `<dir>/current/.podship/compose.sh run --rm --no-deps -T --name
// <container> --entrypoint <argv0> <service> <argv…>`: a one-off container
// of the current release's image, with the service's env file, secrets and
// volumes. Nothing secret is in the registry or in argv.

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../scheduler/scheduler.dart';
import '../server/registry.dart';
import 'scheduler_ops.dart';

/// The registry id of task [name] of [env].
String taskJobId(String project, String env, String name) =>
    'command:$project/$env/$name';

/// The container name of a task run: one at a time per task.
String taskContainer(EnvConfig env, EnvTask t) =>
    '${env.composeProject}-task-${t.name}'.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '-',
    );

/// The argv of a run of [t]: null when it has no command (a disabled
/// placeholder).
List<String>? taskArgv(EnvConfig env, EnvTask t) {
  if (t.command.isEmpty) return null;
  return [
    EnvLayout(env).currentComposeSh,
    'run',
    '--rm',
    '--no-deps',
    '-T',
    '--name',
    taskContainer(env, t),
    '--entrypoint',
    t.command.first,
    t.service ?? env.serverService,
    ...t.command.sublist(1),
  ];
}

/// The registry job of task [t] of [env].
ScheduledJob taskJob(String project, EnvConfig env, EnvTask t) {
  final l = EnvLayout(env);
  return ScheduledJob(
    kind: JobKind.command,
    project: project,
    env: env.name,
    enabled: t.enabled,
    name: t.name,
    run: taskArgv(env, t),
    cwd: l.current,
    path: env.remotePath,
    log: p.posix.join(
      env.podshipHome,
      'log',
      'task-$project-${env.name}-${t.name}.log',
    ),
    at: t.at,
    timeout: t.timeout,
    task: true,
    redact: [l.envFile, l.passwordsFile],
    plain: env.plainEnv,
    container: taskContainer(env, t),
    note: 'from podship.yaml tasks:',
  );
}

/// Rewrites the `scheduled:` commands and the `tasks:` of [env] in [reg]
/// from podship.yaml: a removed one leaves the registry.
void syncCommandJobs(Registry reg, String project, EnvConfig env) {
  for (final id in [
    for (final j in reg.jobs.values)
      if (j.kind == JobKind.command &&
          j.project == project &&
          j.env == env.name)
        j.id,
  ]) {
    reg.removeJob(id);
  }
  for (final c in env.scheduled) {
    reg.putJob(
      ScheduledJob(
        kind: JobKind.command,
        project: project,
        env: env.name,
        name: c.name,
        run: c.run,
        cwd: p.posix.normalize(p.posix.join(env.dir, 'current', c.cwd)),
        path: c.path ?? env.remotePath,
        note: 'from podship.yaml scheduled:',
      ),
    );
  }
  for (final t in env.tasks) {
    reg.putJob(taskJob(project, env, t));
  }
}

/// Plans `task sync`: the tasks of [env] into the registry of its server,
/// without a deploy. Null when the registry already has them.
Plan? planTaskSync(
  String project,
  EnvConfig env, {
  required String registryText,
}) {
  final t = SchedulerTarget.ofEnv(env);
  final reg = Registry.parse(registryText);
  syncCommandJobs(reg, project, env);
  final next = reg.render();
  if (next == registryText ||
      Registry.parse(next).render() == Registry.parse(registryText).render()) {
    return null;
  }
  return Plan('write the tasks of ${env.name} into ${t.registryPath}', [
    RegistryWriteStep(
      'Write ${env.tasks.length} task(s) of $project/${env.name} into ${t.registryPath}',
      t.host,
      t.registryPath,
      header: t.header(),
      base: registryText,
      mine: next,
    ),
  ]);
}

/// `YYYY-MM-DD HH:MM`, local time.
String _when(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${localDate(t)} ${two(t.hour)}:${two(t.minute)}';
}

/// One row per task of [env] for `task list` and `status`: its schedule,
/// whether the server's registry has it, its last run and its next run.
/// [state] is the scheduler's `state.json`; [agentTimes] the times the
/// installed agent fires at (null: unknown); [watched] whether the agent
/// also ticks every few minutes.
List<Map<String, Object?>> taskRows(
  String project,
  EnvConfig env,
  Registry reg,
  Map<String, Object?> state,
  DateTime now, {
  List<String>? agentTimes,
  bool? watched,
}) {
  final jobs = (state['jobs'] as Map?) ?? const {};
  return [
    for (final t in env.tasks)
      () {
        final id = taskJobId(project, env.name, t.name);
        final job = reg.jobs[id];
        final js = jobs[id] is Map ? JobState.fromJson(jobs[id] as Map) : null;
        final at = t.at ?? reg.scheduler.at;
        final synced =
            job != null &&
            job.task &&
            job.enabled == t.enabled &&
            job.at == t.at &&
            job.timeout == t.timeout &&
            '${job.run}' == '${taskArgv(env, t)}';
        final next = job == null || !t.enabled
            ? null
            : nextRun(job, reg.scheduler, js, now);
        final fires =
            watched == true ||
            agentTimes == null ||
            agentTimes.contains(at) ||
            !t.enabled;
        return <String, Object?>{
          'name': t.name,
          'id': id,
          'enabled': t.enabled,
          'schedule': t.schedule,
          'at': at,
          'timeout_s': t.timeout,
          'service': t.service ?? env.serverService,
          'command': t.command,
          'in_registry': job != null,
          'synced': synced,
          'last_run': ?js?.lastRun,
          'last_ok': ?js?.lastOk,
          'last_error': ?js?.lastError,
          'last_duration_s': ?js?.lastDuration,
          if (next != null) 'next_run': _when(next),
          if (!fires)
            'warning':
                'the agent does not fire at $at: run podship scheduler install --env ${env.name}',
        };
      }(),
  ];
}

/// One line for a task row.
String formatTaskRow(Map<String, Object?> r) {
  final b = StringBuffer('${r['name']}  ${r['schedule']}');
  if (r['enabled'] != true) b.write(' (disabled)');
  final last = r['last_run'];
  b.write(
    last == null
        ? '; last: never'
        : '; last: $last ${r['last_ok'] == true ? 'ok' : 'FAILED${r['last_error'] == null ? '' : ' (${r['last_error']})'}'}'
              '${r['last_duration_s'] == null ? '' : ' in ${r['last_duration_s']}s'}',
  );
  if (r['next_run'] != null) b.write('; next: ${r['next_run']}');
  if (r['in_registry'] != true) {
    b.write('; not on the server yet (deploy, or podship task sync)');
  } else if (r['synced'] != true) {
    b.write('; the server has an older version (deploy, or podship task sync)');
  }
  if (r['warning'] != null) b.write('; ${r['warning']}');
  return b.toString();
}
