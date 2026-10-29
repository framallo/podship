// The podship scheduler: one agent per machine, one run per night.
//
// `podship scheduler tick --home <podship home>` runs on the machine itself
// (launchd or systemd starts it at the time in the registry, and once at
// load for the catch-up after a reboot or a long sleep). It reads the jobs
// from `<home>/registry.yaml`, runs the ones that have not run today
// (backups first, then pulls), keeps `<home>/scheduler/state.json`, appends
// to `<home>/log/scheduler.log` and writes a history record per run. A job
// that fails never stops the others, and a job already running (its lock is
// held) is skipped.
//
// Nothing here reads `podship.yaml`: a server has none.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../edit/dotenv.dart';

import '../server/registry.dart';

/// The local date of [t] as `YYYY-MM-DD`.
String localDate(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// What the scheduler remembers about one job.
class JobState {
  JobState({
    this.lastRun,
    this.lastRunDate,
    this.lastOk,
    this.lastError,
    this.lastDuration,
    this.lastStamp,
  });

  factory JobState.fromJson(Map m) => JobState(
    lastRun: m['last_run'] as String?,
    lastRunDate: m['last_run_date'] as String?,
    lastOk: m['last_ok'] as bool?,
    lastError: m['last_error'] as String?,
    lastDuration: (m['last_duration_s'] as num?)?.toInt(),
    lastStamp: m['last_stamp'] as String?,
  );

  /// UTC instant of the last run.
  String? lastRun;

  /// The machine-local date of the last run. A job is due when this is not
  /// today.
  String? lastRunDate;
  bool? lastOk;
  String? lastError;
  int? lastDuration;

  /// The backup stamp the last run produced.
  String? lastStamp;

  Map<String, Object?> toJson() => {
    'last_run': ?lastRun,
    'last_run_date': ?lastRunDate,
    'last_ok': ?lastOk,
    'last_error': ?lastError,
    'last_duration_s': ?lastDuration,
    'last_stamp': ?lastStamp,
  };
}

/// `<home>/scheduler/state.json`.
class SchedulerState {
  SchedulerState({
    Map<String, JobState>? jobs,
    this.lastTick,
    this.lastTickDate,
  }) : jobs = jobs ?? {};

  factory SchedulerState.fromJson(Map m) => SchedulerState(
    jobs: {
      for (final e in ((m['jobs'] as Map?) ?? const {}).entries)
        '${e.key}': JobState.fromJson(e.value as Map),
    },
    lastTick: m['last_tick'] as String?,
    lastTickDate: m['last_tick_date'] as String?,
  );

  final Map<String, JobState> jobs;
  String? lastTick;
  String? lastTickDate;

  Map<String, Object?> toJson() => {
    'last_tick': ?lastTick,
    'last_tick_date': ?lastTickDate,
    'jobs': {for (final e in jobs.entries) e.key: e.value.toJson()},
  };

  static String path(String home) => p.join(home, 'scheduler', 'state.json');

  static SchedulerState load(String home) {
    final f = File(path(home));
    if (!f.existsSync()) return SchedulerState();
    try {
      return SchedulerState.fromJson(jsonDecode(f.readAsStringSync()) as Map);
    } catch (_) {
      return SchedulerState();
    }
  }

  void save(String home) {
    final f = File(path(home))..parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
      );
    tmp.renameSync(f.path);
  }
}

/// The jobs due at [now]: enabled jobs that did not run on today's local
/// date, once the local time is at or after the job's time (its own `at`, a
/// task's `daily HH:MM`, else the nightly time `scheduler.at`), in run
/// order (backups, then pulls, then commands and tasks). The agent ticks
/// every few minutes for the watch, so the time of day matters: a tick at
/// 00:10 runs nothing until `at`. One missed night is caught up with one
/// run at the first tick after `at`; several missed nights still give one
/// run.
List<ScheduledJob> dueJobs(
  Registry registry,
  SchedulerState state,
  DateTime now,
) {
  final today = localDate(now);
  return [
    for (final j in registry.orderedJobs)
      if (j.enabled &&
          timeReached(now, j.timeOn(registry.scheduler)) &&
          state.jobs[j.id]?.lastRunDate != today)
        j,
  ];
}

/// Whether the local time of [now] is at or after [at] (`HH:MM`).
bool timeReached(DateTime now, String at) =>
    now.hour * 60 + now.minute >=
    int.parse(at.substring(0, 2)) * 60 + int.parse(at.substring(3, 5));

/// A task the scheduler sees for the first time (a deploy or `task sync`
/// just wrote it) never runs at that tick: when its time already passed
/// today, it is marked as run today, so its first run is the next
/// occurrence. A destructive task (a demo reset) must not fire in the
/// afternoon because a deploy added it. Returns the ids it marked.
List<String> settleNewTasks(
  Registry registry,
  SchedulerState state,
  DateTime now,
) {
  final marked = <String>[];
  for (final j in registry.jobs.values) {
    if (!j.task || state.jobs[j.id] != null) continue;
    if (!timeReached(now, j.timeOn(registry.scheduler))) continue;
    state.jobs[j.id] = JobState(lastRunDate: localDate(now));
    marked.add(j.id);
  }
  return marked;
}

/// When [job] runs next, from [now] and its state: today at its time when
/// it has not run today and the time is ahead, else tomorrow at its time
/// (a due job runs at the next tick, which this reports as now). Null for
/// a disabled job.
DateTime? nextRun(
  ScheduledJob job,
  SchedulerSettings nightly,
  JobState? state,
  DateTime now,
) {
  if (!job.enabled) return null;
  final at = job.timeOn(nightly);
  final today = DateTime(
    now.year,
    now.month,
    now.day,
    int.parse(at.substring(0, 2)),
    int.parse(at.substring(3, 5)),
  );
  final ranToday = state?.lastRunDate == localDate(now);
  if (!timeReached(now, at)) return ranToday ? _tomorrow(today) : today;
  if (ranToday || (job.task && state == null)) return _tomorrow(today);
  return now;
}

/// The same wall-clock time on the next day (a DST change keeps 03:00).
DateTime _tomorrow(DateTime t) =>
    DateTime(t.year, t.month, t.day + 1, t.hour, t.minute);

/// The podship executable for a job that calls podship (a pull). A compiled
/// podship is itself; `dart run` or a pub snapshot needs the Dart VM first.
(String, List<String>) podshipCommand() {
  final exe = Platform.resolvedExecutable;
  final script = Platform.script.toFilePath();
  final viaVm =
      p.basenameWithoutExtension(exe) == 'dart' ||
      script.endsWith('.dart') ||
      script.endsWith('.snapshot');
  return viaVm ? (exe, [script]) : (exe, const []);
}

/// The result of one job run.
class JobRun {
  JobRun(
    this.job,
    this.ok,
    this.duration, {
    this.error,
    this.stamp,
    this.skipped = false,
    this.release,
  });
  final ScheduledJob job;

  /// The release a task ran in.
  final String? release;
  final bool ok;
  final Duration duration;
  final String? error;
  final String? stamp;

  /// The job was already running (its lock was held).
  final bool skipped;

  Map<String, Object?> toJson() => {
    'job': job.id,
    'ok': ok,
    'skipped': skipped,
    'duration_s': duration.inSeconds,
    'error': ?error,
    'stamp': ?stamp,
    'release': ?release,
  };
}

/// Runs the jobs of this machine.
class JobRunner {
  JobRunner(
    this.home, {
    DateTime Function()? clock,
    this.echo,
    this.backupCommand,
    this.onFailure,
    this.removeContainer,
  }) : clock = clock ?? DateTime.now;

  /// Called with every failed (not skipped) run of a [tick]: the scheduler
  /// command sends `scheduler_job_failed` through the machine's channels.
  /// A manual run (`run-once`, `task run`) reports its own failure.
  final Future<void> Function(JobRun run)? onFailure;

  /// Removes a task's container (tests); default `docker rm -f <name>`.
  final Future<void> Function(ScheduledJob job, String container)?
  removeContainer;

  /// The command of a backup job (tests); default
  /// `podship agent backup --conf <conf>` with this podship.
  final List<String> Function(ScheduledJob job)? backupCommand;

  /// The podship home of this machine (`--home`).
  final String home;
  final DateTime Function() clock;

  /// Also prints every log line (for `run-once` in a terminal).
  final void Function(String line)? echo;

  String get registryPath => p.join(home, 'registry.yaml');
  String get logPath => p.join(home, 'log', 'scheduler.log');
  String get lockDir => p.join(home, 'scheduler', 'locks');

  Registry readRegistry() {
    final f = File(registryPath);
    return Registry.parse(f.existsSync() ? f.readAsStringSync() : '');
  }

  /// Appends one line to `scheduler.log`.
  void log(String message) {
    final line = '${clock().toIso8601String()} $message';
    echo?.call(line);
    try {
      File(logPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Takes the lock [name]. Returns null when another process holds it.
  RandomAccessFile? _lock(String name) {
    Directory(lockDir).createSync(recursive: true);
    final f = File(
      p.join(lockDir, '$name.lock'),
    ).openSync(mode: FileMode.append);
    try {
      f.lockSync(FileLock.exclusive);
      return f;
    } on FileSystemException {
      f.closeSync();
      return null;
    }
  }

  void _unlock(RandomAccessFile f) {
    try {
      f.unlockSync();
    } catch (_) {}
    f.closeSync();
  }

  /// Marks every job without state as run today, so the first tick after an
  /// install (launchd runs the agent at load) runs nothing until tonight.
  /// Returns the ids it seeded.
  List<String> seed() {
    final reg = readRegistry();
    final state = SchedulerState.load(home);
    final now = clock();
    final today = localDate(now);
    final seeded = <String>[];
    for (final j in reg.jobs.values) {
      // A task whose time is still ahead today runs today at its time.
      if (j.task && !timeReached(now, j.timeOn(reg.scheduler))) continue;
      if (state.jobs[j.id]?.lastRunDate == null) {
        state.jobs[j.id] = (state.jobs[j.id] ?? JobState())
          ..lastRunDate = today;
        seeded.add(j.id);
      }
    }
    state.save(home);
    if (seeded.isNotEmpty) {
      log('seeded ${seeded.join(', ')}: first run tonight');
    }
    return seeded;
  }

  /// Whether a [tick] would run anything now: the first tick (it seeds), or
  /// a due job.
  bool nightlyDue() {
    if (!File(SchedulerState.path(home)).existsSync()) return true;
    return dueJobs(
      readRegistry(),
      SchedulerState.load(home),
      clock(),
    ).isNotEmpty;
  }

  /// The nightly run. Runs every due job in order. Never throws.
  Future<List<JobRun>> tick({bool force = false}) async {
    final lock = _lock('tick');
    if (lock == null) {
      log('tick: another tick is running; nothing to do');
      return const [];
    }
    final runs = <JobRun>[];
    try {
      final now = clock();
      final reg = readRegistry();
      final state = SchedulerState.load(home);
      final firstTick = !File(SchedulerState.path(home)).existsSync();
      state
        ..lastTick = now.toUtc().toIso8601String()
        ..lastTickDate = localDate(now);
      if (firstTick && !force) {
        // Never a burst right after the install: everything starts tonight.
        final today = localDate(now);
        for (final j in reg.jobs.values) {
          if (j.task && !timeReached(now, j.timeOn(reg.scheduler))) continue;
          state.jobs[j.id] = JobState(lastRunDate: today);
        }
        state.save(home);
        log(
          'tick: first run, ${reg.jobs.length} job(s) start tonight at ${reg.scheduler.at}',
        );
        return const [];
      }
      if (!force) {
        for (final id in settleNewTasks(reg, state, now)) {
          final j = reg.jobs[id]!;
          log(
            '$id: new task; first run tomorrow at ${j.timeOn(reg.scheduler)}',
          );
        }
      }
      final due = force ? reg.orderedJobs : dueJobs(reg, state, now);
      state.save(home);
      if (due.isEmpty) {
        log('tick: nothing due (${reg.jobs.length} job(s))');
        return const [];
      }
      log('tick: ${due.length} due: ${due.map((j) => j.id).join(', ')}');
      for (final j in due) {
        final run = await runJob(j, state: state);
        runs.add(run);
        if (!run.ok && !run.skipped && onFailure != null) {
          try {
            await onFailure!(run);
          } catch (e) {
            log('${j.id}: could not send the failure notification: $e');
          }
        }
      }
    } catch (e) {
      log('tick failed: $e');
    } finally {
      _unlock(lock);
    }
    return runs;
  }

  /// Runs [job] now, whatever its state, and records the run. Returns a
  /// skipped run when the job is already running (its lock is held: the
  /// agent and `task run` take the same lock, so two runs never overlap).
  /// [actor] goes into the history record.
  Future<JobRun> runJob(
    ScheduledJob job, {
    SchedulerState? state,
    String actor = 'podship-scheduler',
  }) async {
    final lock = _lock(job.id.replaceAll('/', '_'));
    if (lock == null) {
      log('${job.id}: already running; skipped');
      return JobRun(
        job,
        false,
        Duration.zero,
        error: 'already running',
        skipped: true,
      );
    }
    final started = clock();
    final watch = Stopwatch()..start();
    final transcript = StringBuffer();
    final secrets = taskSecrets(job);
    String? stamp;
    String? error;
    final release = job.task ? _release(job) : null;
    try {
      final (exe, args, env, cwd) = _command(job);
      // A killed run may have left the task's container: we hold the lock,
      // so no other run owns it.
      if (job.container != null) await _removeContainer(job);
      log('${job.id}: start${release == null ? '' : ' (release $release)'}');
      final proc = await Process.start(
        exe,
        args,
        environment: env,
        workingDirectory: cwd,
        includeParentEnvironment: true,
      );
      await proc.stdin.close();
      var timedOut = false;
      Timer? kill;
      final limit = job.timeout == null
          ? null
          : Timer(Duration(seconds: job.timeout!), () {
              timedOut = true;
              log('${job.id}: timeout after ${job.timeout}s; stopping it');
              proc.kill();
              kill = Timer(const Duration(seconds: 10), () {
                proc.kill(ProcessSignal.sigkill);
              });
            });
      Future<void> pump(Stream<List<int>> s) => s
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((raw) {
            final l = redact(raw, secrets);
            transcript.writeln(l);
            echo?.call('  $l');
            final m =
                RegExp(r'PODSHIP_BACKUP_STAMP=(\S+)').firstMatch(l) ??
                RegExp(r'\[backup\] stamp (\S+)').firstMatch(l);
            if (m != null) stamp ??= m[1];
          });
      final pumps = Future.wait([pump(proc.stdout), pump(proc.stderr)]);
      final code = await proc.exitCode;
      limit?.cancel();
      kill?.cancel();
      // A grandchild may keep a pipe open after a kill: do not wait for it.
      await pumps.timeout(const Duration(seconds: 5), onTimeout: () => []);
      if (timedOut) {
        error = 'timeout after ${job.timeout}s';
        if (job.container != null) await _removeContainer(job);
      } else if (code != 0) {
        error = 'exit code $code';
      }
    } catch (e) {
      error = redact('$e', secrets);
    }
    watch.stop();
    final run = JobRun(
      job,
      error == null,
      watch.elapsed,
      error: error,
      stamp: stamp,
      release: release,
    );
    log(
      '${job.id}: ${error == null ? 'ok' : 'failed ($error)'} in ${watch.elapsed.inSeconds}s'
      '${stamp == null ? '' : ' stamp $stamp'}',
    );
    if (job.log != null) {
      try {
        File(job.log!)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(transcript.toString(), mode: FileMode.append);
      } catch (_) {}
    }
    final st = state ?? SchedulerState.load(home);
    st.jobs[job.id] = JobState(
      lastRun: started.toUtc().toIso8601String(),
      lastRunDate: localDate(started),
      lastOk: error == null,
      lastError: error,
      lastDuration: watch.elapsed.inSeconds,
      lastStamp: stamp,
    );
    try {
      st.save(home);
    } catch (e) {
      log('could not save the state: $e');
    }
    try {
      _writeHistory(job, run, started, transcript.toString(), actor);
    } catch (e) {
      log('could not write the history record: $e');
    }
    _unlock(lock);
    return run;
  }

  /// The release `<dir>/current` points at, for a task's history record.
  String? _release(ScheduledJob job) {
    final cwd = job.cwd;
    if (cwd == null) return null;
    try {
      return p.basename(Link(cwd).targetSync());
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeContainer(ScheduledJob job) async {
    final name = job.container!;
    try {
      if (removeContainer != null) {
        await removeContainer!(job, name);
        return;
      }
      // Through sh, so the job's PATH finds docker (Colima, Homebrew).
      await Process.run(
        '/bin/sh',
        ['-c', r'docker rm -f "$1" >/dev/null 2>&1 || true', 'sh', name],
        environment: {
          if (job.path != null)
            'PATH': '${job.path}:${Platform.environment['PATH'] ?? ''}',
        },
      );
    } catch (e) {
      log('${job.id}: could not remove the container $name: $e');
    }
  }

  /// The process of a job.
  (String, List<String>, Map<String, String>, String?) _command(
    ScheduledJob job,
  ) {
    final env = <String, String>{
      if (job.path != null)
        'PATH': '${job.path}:${Platform.environment['PATH'] ?? ''}',
      'PODSHIP_SCHEDULER': '1',
    };
    switch (job.kind) {
      case JobKind.backup:
        final conf = job.conf;
        if (conf == null) throw StateError('${job.id} has no conf');
        // `script` (the bash script of older podships) is ignored: the
        // backup runs in this podship.
        final custom = backupCommand?.call(job);
        if (custom != null) {
          return (custom.first, custom.sublist(1), env, home);
        }
        final (exe, pre) = podshipCommand();
        return (exe, [...pre, 'agent', 'backup', '--conf', conf], env, home);
      case JobKind.command:
        final run = job.run;
        if (run == null || run.isEmpty) {
          throw StateError('${job.id} has no run');
        }
        return (run.first, run.sublist(1), env, job.cwd ?? home);
      case JobKind.pull:
        final dir = job.projectDir;
        if (dir == null) throw StateError('${job.id} has no project_dir');
        final (exe, pre) = podshipCommand();
        return (
          exe,
          [
            ...pre,
            '-C',
            dir,
            'backup',
            'pull',
            '--env',
            job.env,
            '--yes',
            '--via',
            'ssh',
          ],
          env,
          dir,
        );
    }
  }

  /// A history record like the ones podship operations write, under
  /// `<home>/history/<project>/<env>/`.
  void _writeHistory(
    ScheduledJob job,
    JobRun run,
    DateTime started,
    String transcript,
    String actor,
  ) {
    final dir = p.join(home, 'history', job.project, job.env);
    final s = started.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${s.year}${two(s.month)}${two(s.day)}T${two(s.hour)}${two(s.minute)}${two(s.second)}Z';
    final op = switch (job.kind) {
      JobKind.backup => 'backup now',
      JobKind.pull => 'backup pull',
      JobKind.command =>
        job.task ? 'task ${job.name}' : 'scheduled ${job.name}',
    };
    final base = '$stamp-${op.replaceAll(' ', '-')}';
    final ended = s.add(run.duration);
    final json = {
      'operation': op,
      'ok': run.ok,
      'duration_ms': run.duration.inMilliseconds,
      'project': job.project,
      'env': job.env,
      'host': Platform.localHostname,
      'error': ?run.error,
      'release': ?run.release,
      'dry_run': false,
      'data': {
        'job': job.id,
        'scheduled': actor == 'podship-scheduler',
        'stamp': ?run.stamp,
        if (job.task) 'task': job.name,
      },
      'actor': actor,
      'started_at': s.toIso8601String(),
      'ended_at': ended.toIso8601String(),
      'log': p.join(dir, '$base.log'),
    };
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, '$base.json')).writeAsStringSync('${jsonEncode(json)}\n');
    File(p.join(dir, '$base.log')).writeAsStringSync(transcript);
  }
}

/// The podship home of this machine for jobs that run here (pulls):
/// `PODSHIP_HOME`, else the home of an environment with `host: local` in
/// [localEnvHome], else `~/podship`.
String localPodshipHome({String? localEnvHome}) =>
    Platform.environment['PODSHIP_HOME'] ??
    localEnvHome ??
    p.join(Platform.environment['HOME'] ?? '/srv', 'podship');

/// The secret values a job's output must not show: the values of the
/// files in [ScheduledJob.redact] on this machine (`.env`, minus the
/// [ScheduledJob.plain] names, and every value of `passwords.yaml`) of 8
/// characters or more, longest first. Read at run time, never stored.
List<String> taskSecrets(ScheduledJob job) {
  final out = <String>{};
  for (final path in job.redact) {
    final f = File(path);
    if (!f.existsSync()) continue;
    String text;
    try {
      text = f.readAsStringSync();
    } catch (_) {
      continue;
    }
    if (path.endsWith('.yaml') || path.endsWith('.yml')) {
      void walk(Object? v) {
        if (v is Map) {
          v.values.forEach(walk);
        } else if (v is List) {
          v.forEach(walk);
        } else if (v != null) {
          out.add('$v');
        }
      }

      try {
        walk(loadYaml(text));
      } catch (_) {}
    } else {
      final env = DotEnv(text);
      for (final n in env.names) {
        if (job.plain.contains(n) || env.markedPlain(n)) continue;
        final v = env.get(n);
        if (v != null) out.add(v);
      }
    }
  }
  return [
    for (final v in out)
      if (v.trim().length >= 8) v,
  ]..sort((a, b) => b.length.compareTo(a.length));
}

/// [line] with every value of [secrets] replaced by `***`.
String redact(String line, List<String> secrets) {
  var l = line;
  for (final s in secrets) {
    if (l.contains(s)) l = l.replaceAll(s, '***');
  }
  return l;
}
