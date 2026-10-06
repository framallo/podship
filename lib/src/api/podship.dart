// The podship library: every operation, typed, with a live event stream.
//
// The CLI is a thin layer over this class. A UI can use it the same way:
//
//   final podship = Podship(PodshipConfig.load('/path/to/project'));
//   final op = podship.deploy('staging');
//   op.events.listen(print);
//   final result = await op.result;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../edit/dotenv.dart';
import '../edit/passwords.dart';
import '../ops/backup_ops.dart';
import '../ops/db_ops.dart';
import '../ops/context.dart';
import '../ops/deploy.dart';
import '../ops/domain_ops.dart';
import '../ops/release_ops.dart';
import '../ops/resolve.dart';
import '../ops/scripts.dart';
import '../ops/secrets.dart';
import '../ops/server_ops.dart';
import '../ops/state.dart';
import '../ops/tests.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../server/registry.dart';
import '../util/log.dart';
import '../protocol/tokens.dart';
import '../providers/providers.dart';
import 'events.dart';
import 'github.dart';
import 'history.dart';
import 'lock.dart';
import 'render.dart';
import 'models.dart';
import '../protocol/protocol.dart' show OperationRequest;

export '../ops/deploy.dart' show DeployOptions;
export '../ops/state.dart' show ReleaseInfo;

/// The package version, written into history records.
const podshipVersion = '0.2.0';

/// A running operation: its events, and its result when it ends.
class Operation {
  Operation._(this.request, this._start);

  /// The protocol request of this operation: its stable name and params.
  /// A client can send it to a console instead of running it here.
  final OperationRequest request;
  final (Stream<PodshipEvent>, Future<OperationResult>) Function() _start;
  (Stream<PodshipEvent>, Future<OperationResult>)? _running;

  (Stream<PodshipEvent>, Future<OperationResult>) get _run =>
      _running ??= _start();

  /// Every event, from [OperationStarted] to [OperationFinished]. A single
  /// listener; events are kept until someone listens. The operation starts
  /// when [events] or [result] is first read.
  Stream<PodshipEvent> get events => _run.$1;

  /// The result. It completes after the last event, and never throws: a
  /// failure is a result with `ok: false`.
  Future<OperationResult> get result => _run.$2;
}

/// What an operation records while it runs.
class OpRecord {
  String? release;
  String? previousRelease;
  final Map<String, Object?> data = {};

  /// Keys of [data] that must not reach the server's history (a password
  /// shown once, for example).
  final Set<String> sensitive = {};
}

class Podship {
  Podship(
    this.config, {
    this.sshOptions = const [],
    this.dryRun = false,
    this.verbose = false,
    String? actor,
  }) : actor = actor ?? defaultActor();

  final PodshipConfig config;

  /// Extra ssh options, like `['-i', key]` in CI.
  final List<String> sshOptions;

  /// Plan only: operations emit their plan and change nothing.
  final bool dryRun;
  final bool verbose;

  /// Who runs the operations, for history records.
  final String actor;

  /// `git config user.email`, or `$USER@host`.
  static String defaultActor() {
    try {
      final r = Process.runSync('git', ['config', 'user.email']);
      final e = (r.stdout as String).trim();
      if (r.exitCode == 0 && e.isNotEmpty) return e;
    } catch (_) {}
    return '${Platform.environment['USER'] ?? 'unknown'}@${Platform.localHostname}';
  }

  Ssh get _ssh => Ssh(extraOptions: sshOptions, verbose: verbose);

  Ctx _ctx(Log log, {bool? dry}) => Ctx(
    config: config,
    ssh: _ssh,
    log: log,
    dryRun: dry ?? dryRun,
    yes: true,
  );

  /// A context for read operations, whose log goes nowhere.
  Ctx get _readCtx => _ctx(Log.silent(), dry: false);

  EnvConfig env(String name) => config.env(name);

  Future<({EnvState state, ResolvedEnv r})> _load(Ctx ctx, EnvConfig e) async {
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

  /// Runs [body] as an operation named [name] on [envName].
  Operation _op(
    String name,
    String? envName,
    Map<String, Object?> params,
    Future<void> Function(Ctx ctx, OpRecord rec) body, {
    bool history = true,
    bool lock = true,
  }) {
    final events = StreamController<PodshipEvent>();
    final transcript = StringBuffer();
    void emit(PodshipEvent e) {
      transcript.writeln(renderEventText(e, verbose: true) ?? '');
      events.add(e);
    }

    final log = Log(emit, verbose: verbose);
    final e = envName == null ? null : config.env(envName);
    final rec = OpRecord();
    Future<OperationResult> run() async {
      final watch = Stopwatch()..start();
      emit(
        OperationStarted(
          name,
          project: config.project,
          env: e?.name,
          host: e?.host,
          dryRun: dryRun,
        ),
      );
      String? error;
      final ctx = _ctx(log);
      var locked = false;
      try {
        if (lock && e != null && !dryRun) {
          await acquireLock(ctx, e, operation: name, actor: actor);
          locked = true;
        }
        await body(ctx, rec);
      } catch (x) {
        error =
            x is StepError ||
                x is Aborted ||
                x is ConfigException ||
                x is RemoteException ||
                x is RegistryConflict
            ? '$x'
            : '$x';
      }
      if (locked) {
        try {
          await releaseLock(ctx, e!);
        } catch (x) {
          log.warn('could not release the lock: $x');
        }
      }
      var result = OperationResult(
        operation: name,
        ok: error == null,
        duration: watch.elapsed,
        project: config.project,
        env: e?.name,
        host: e?.host,
        release: rec.release,
        previousRelease: rec.previousRelease,
        error: error,
        dryRun: dryRun,
        data: rec.data,
      );
      if (history && e != null && !dryRun) {
        try {
          final path = await writeHistory(
            ctx,
            e,
            result,
            actor,
            transcript.toString(),
            rec.sensitive,
          );
          result = result.withHistory(path);
        } catch (x) {
          log.warn('could not write the history record: $x');
        }
      }
      emit(OperationFinished(result));
      await events.close();
      return result;
    }

    return Operation._(
      OperationRequest(
        operation: name.replaceAll(' ', '.'),
        project: config.project,
        env: envName,
        params: {
          for (final e in params.entries)
            if (e.value != null) e.key: e.value,
        },
        dryRun: dryRun,
      ),
      () => (events.stream, run()),
    );
  }

  // ---------------------------------------------------------------- releases

  /// Builds and starts a new release; rolls back if it is not healthy.
  /// [skipTestsReason] skips the test stage (recorded in history). For an
  /// environment in `tests.gate` (production by default), a commit must have
  /// passed its tests here or in another environment; otherwise the caller
  /// must pass [confirmedUntested] after the user typed the environment name.
  Operation deploy(
    String envName, {
    DeployOptions options = const DeployOptions(),
    String? ref,
    String? skipTestsReason,
    bool confirmedUntested = false,
  }) => _op(
    'deploy',
    envName,
    {
      'ref': ref,
      'skip_web': options.skipWeb,
      'skip_backup': options.skipBackup,
      'public_check': options.publicCheck,
      'skip_tests_reason': skipTestsReason,
      if (confirmedUntested) 'confirm_env': envName,
    },
    (ctx, rec) async {
      final e = config.env(envName);
      final source = options.source ?? config.build.source;
      final git = await GitInfo.read(config.root, ref ?? config.build.ref);
      if (source == SourceMode.git && git.sha == 'nogit') {
        throw Aborted(
          'ref "${git.ref}" not found; use worktree mode outside git',
        );
      }
      if (source == SourceMode.git) {
        for (final f in composeFilesOf(config, e)) {
          final r = await Process.run('git', [
            'cat-file',
            '-e',
            '${git.sha}:$f',
          ], workingDirectory: config.root);
          if (r.exitCode != 0) {
            throw Aborted('$f is not in commit ${git.sha}; commit it first');
          }
        }
      }
      rec.data['sha'] = git.sha;
      final skip = skipTestsReason != null;
      final suites = config.tests.forEnv(e.name);
      await _testGate(
        ctx,
        rec,
        e,
        git.sha,
        skip: skip,
        reason: skipTestsReason,
        willRun: !skip && suites.isNotEmpty,
        confirmed: confirmedUntested,
      );
      final run = TestRun();
      final (:state, :r) = await _load(ctx, e);
      rec.previousRelease = state.current;
      final snap = await Directory.systemTemp.createTemp('podship-release-');
      try {
        final plan = planDeploy(
          ctx: ctx,
          r: r,
          state: state,
          git: git,
          now: DateTime.now(),
          snapshot: snap.path,
          options: DeployOptions(
            source: options.source,
            skipWeb: options.skipWeb,
            skipBackup: options.skipBackup,
            skipHooks: options.skipHooks,
            publicCheck: options.publicCheck,
            skipTests: skip || options.skipTests,
            tests: run,
          ),
        );
        final id = plan.title.split(' as ').last;
        final gh = GitHub(config, ctx.log);
        final deployment = dryRun
            ? null
            : await gh.startDeployment(e, git.sha, id);
        try {
          await ctx.run(plan);
        } catch (x) {
          // The recovery may have switched back; report what runs now.
          rec.release = dryRun
              ? state.current
              : (await fetchState(_readCtx, e)).current;
          if (!dryRun) {
            await gh.finishDeployment(
              e,
              deployment,
              ok: false,
              description: '$x',
            );
            await gh.commitStatus(
              e,
              git.sha,
              ok: false,
              description: 'deploy to ${e.name} failed',
            );
          }
          rethrow;
        } finally {
          if (run.results.isNotEmpty) {
            rec.data['tests'] = {
              'ok': run.ok,
              'suites': [for (final t in run.results) t.toJson()],
              'record': ?run.recordPath,
            };
          }
        }
        rec.release = dryRun ? state.current : id;
        rec.data['new_release'] = id;
        if (!dryRun) {
          await gh.finishDeployment(e, deployment, ok: true, description: id);
          await gh.commitStatus(
            e,
            git.sha,
            ok: true,
            description: 'running on ${e.name} as $id',
          );
          await gh.tag(e, git.sha, id);
          final url = await gh.release(
            e,
            git.sha,
            id,
            _shaOf(state, state.current),
            tests:
                (rec.data['tests'] as Map<String, Object?>?) ??
                (rec.data['tests_passed_in'] == null
                    ? null
                    : {'passed_in': rec.data['tests_passed_in']}),
          );
          if (url != null) rec.data['github_release'] = url;
        }
      } finally {
        await snap.delete(recursive: true);
      }
    },
  );

  static String _short(String sha) =>
      sha.length > 7 ? sha.substring(0, 7) : sha;

  /// The git commit of release [id], from its metadata.
  static String? _shaOf(EnvState state, String? id) {
    if (id == null) return null;
    final sha = state.releases.where((r) => r.id == id).firstOrNull?.meta?.sha;
    return sha == null || sha.length < 7 || sha == 'nogit' ? null : sha;
  }

  /// Checks the test gate before a deploy or a promotion to [e].
  Future<void> _testGate(
    Ctx ctx,
    OpRecord rec,
    EnvConfig e,
    String sha, {
    required bool skip,
    required String? reason,
    required bool willRun,
    required bool confirmed,
  }) async {
    if (skip) {
      if (reason == null || reason.trim().isEmpty) {
        throw Aborted('skipping tests needs a reason (--reason)');
      }
      rec.data['tests'] = {'skipped': true, 'reason': reason};
    }
    // Projects without test suites have no gate.
    if (willRun ||
        config.tests.suites.isEmpty ||
        !config.tests.gate.contains(e.name))
      return;
    final where = await findPassingTests(ctx, sha);
    if (where != null) {
      ctx.log.info('tests of ${_short(sha)} passed in the $where deploy');
      rec.data['tests_passed_in'] = where;
      return;
    }
    if (!confirmed) {
      throw Aborted(
        '${e.name} only takes commits whose tests passed, and ${_short(sha)} has no passing test run. '
        'Run its tests (deploy it to staging first), or skip them with --skip-tests --reason "…" and type "${e.name}" to confirm.',
      );
    }
    ctx.log.warn(
      'deploying ${_short(sha)} to ${e.name} without passing tests: $reason',
    );
    rec.data['untested'] = true;
  }

  /// Switches to a previous release (code only), or to [to]. With [withDb],
  /// restores that backup first.
  Operation rollback(String envName, {String? to, String? withDb}) => _op(
    'rollback',
    envName,
    {
      'to': to,
      'with_db': withDb,
      if (withDb != null) 'confirm_project': config.project,
    },
    (ctx, rec) async {
      final e = config.env(envName);
      final (:state, :r) = await _load(ctx, e);
      if (withDb != null && e.backup == null) {
        throw Aborted('${e.name} has no backup settings');
      }
      final plan = planRollback(
        ctx: ctx,
        r: r,
        state: state,
        to: to,
        withDb: withDb,
      );
      rec.previousRelease = state.current;
      if (withDb != null) rec.data['with_db'] = withDb;
      try {
        await ctx.run(plan);
        rec.release = dryRun
            ? state.current
            : plan.steps
                  .whereType<RemoteStep>()
                  .firstWhere((s) => s.title.startsWith('Switch to '))
                  .title
                  .substring(10);
        if (!dryRun && rec.release != null) {
          final gh = GitHub(config, ctx.log);
          final fromSha = _shaOf(state, state.current);
          final toSha = _shaOf(state, rec.release);
          if (fromSha != null) {
            await gh.markInactive(e, fromSha);
            await gh.noteRollback(e, fromSha, rec.release!);
          }
          if (toSha != null) {
            final d = await gh.startDeployment(e, toSha, rec.release!);
            await gh.finishDeployment(
              e,
              d,
              ok: true,
              description: 'rollback to ${rec.release}',
            );
            await gh.commitStatus(
              e,
              toSha,
              ok: true,
              description: 'running on ${e.name} as ${rec.release} (rollback)',
            );
          }
        }
      } catch (_) {
        rec.release = (await fetchState(_readCtx, e)).current;
        rethrow;
      }
    },
  );

  /// Recreates the containers of the current release.
  Operation restart(String envName, {List<String> services = const []}) =>
      _op('restart', envName, {'services': services}, (ctx, rec) async {
        final (:state, :r) = await _load(ctx, config.env(envName));
        rec.release = state.current;
        await ctx.run(
          planRestart(ctx: ctx, r: r, state: state, services: services),
        );
      });

  /// Runs on [toEnv] the exact release that runs on [fromEnv].
  Operation promote(
    String fromEnv,
    String toEnv, {
    String? release,
    String? skipTestsReason,
    bool confirmedUntested = false,
  }) => _op(
    'promote',
    toEnv,
    {
      'from': fromEnv,
      'release': release,
      'skip_tests_reason': skipTestsReason,
      if (confirmedUntested) 'confirm_env': toEnv,
    },
    (ctx, rec) async {
      final from = config.env(fromEnv), to = config.env(toEnv);
      final fromState = await fetchState(ctx, from);
      final id = release ?? fromState.current;
      if (id == null) throw Aborted('nothing runs on ${from.name}');
      final (:state, :r) = await _load(ctx, to);
      rec.previousRelease = state.current;
      rec.data['from'] = from.name;
      final sha = fromState.releases
          .where((x) => x.id == id)
          .firstOrNull
          ?.meta
          ?.sha;
      if (sha != null && sha.length >= 7) {
        rec.data['sha'] = sha;
        await _testGate(
          ctx,
          rec,
          to,
          sha,
          skip: skipTestsReason != null,
          reason: skipTestsReason,
          willRun: false,
          confirmed: confirmedUntested,
        );
      }
      if (from.host != to.host && !dryRun) {
        final a = (await ctx.query(
          from,
          "docker info --format '{{.Architecture}}'",
        )).trim();
        final b = (await ctx.query(
          to,
          "docker info --format '{{.Architecture}}'",
        )).trim();
        if (a != b) {
          final sha =
              fromState.releases.firstWhere((x) => x.id == id).meta?.sha ?? id;
          throw Aborted(
            '${from.name} ($a) and ${to.name} ($b) have different CPU architectures, so images cannot move. '
            'Deploy the same commit instead: podship deploy --env ${to.name} --ref $sha',
          );
        }
      }
      final work = await Directory.systemTemp.createTemp('podship-promote-');
      try {
        await ctx.run(
          await planPromote(
            ctx: ctx,
            from: from,
            fromState: fromState,
            to: r,
            toState: state,
            release: id,
            workDir: work.path,
          ),
        );
        rec.release = dryRun ? state.current : id;
        final psha = _shaOf(fromState, id);
        if (!dryRun && psha != null) {
          final gh = GitHub(config, ctx.log);
          final d = await gh.startDeployment(to, psha, id);
          await gh.finishDeployment(
            to,
            d,
            ok: true,
            description: 'promoted from ${from.name}',
          );
          await gh.commitStatus(
            to,
            psha,
            ok: true,
            description: 'running on ${to.name} as $id',
          );
          await gh.tag(to, psha, id);
          final url = await gh.release(
            to,
            psha,
            id,
            _shaOf(state, state.current),
          );
          if (url != null) rec.data['github_release'] = url;
        }
      } catch (_) {
        rec.release = (await fetchState(_readCtx, to)).current;
        rethrow;
      } finally {
        await work.delete(recursive: true);
      }
    },
  );

  /// Records a setup that runs already as a release, without restarting it.
  Operation adopt(String envName, {String? composeDir}) =>
      _op('adopt', envName, {'compose_dir': composeDir}, (ctx, rec) async {
        final e = config.env(envName);
        final dir = composeDir ?? e.dir;
        final (:state, :r) = await _load(ctx, e);
        final scan = await scanForAdopt(ctx, e, dir, composeFilesOf(config, e));
        final work = await Directory.systemTemp.createTemp('podship-adopt-');
        try {
          final plan = planAdopt(
            ctx: ctx,
            r: r,
            state: state,
            scan: scan,
            composeDir: dir,
            now: DateTime.now(),
            workDir: work.path,
          );
          await ctx.run(plan);
          rec.release = plan.title.split(' as ').last;
        } finally {
          await work.delete(recursive: true);
        }
      });

  /// Registers the environment in the server registry.
  Operation link(String envName) => _op('link', envName, const {}, (
    ctx,
    rec,
  ) async {
    final e = config.env(envName);
    final (:state, :r) = await _load(ctx, e);
    final reg = state.registry..put(r.entry);
    await ctx.run(
      Plan('link ${config.project}/${e.name} on ${e.host}', [
        RemoteStep(
          'Write the registry',
          e.host,
          ctx.header(e) +
              installAssets(e) +
              writeRegistry(e, state.registryText, reg.render()),
        ),
      ]),
    );
    rec.data['ports'] = r.ports;
    if (r.backupSchedule != null) {
      rec.data['backup_schedule'] = r.backupSchedule;
    }
    ctx.log.info(
      'ports: ${r.ports.entries.map((x) => '${x.key}=${x.value}').join(' ')}'
      '${r.backupSchedule == null ? '' : '; backups: ${r.backupSchedule}'}',
    );
  });

  /// Removes an environment completely.
  Operation destroy(String envName, {bool purgeBackups = false}) => _op(
    'destroy',
    envName,
    {'purge_backups': purgeBackups, 'confirm_project': config.project},
    (ctx, rec) async {
      final e = config.env(envName);
      final (:state, :r) = await _load(ctx, e);
      final macos =
          !dryRun && (await ctx.query(e, 'uname -s')).trim() == 'Darwin';
      rec.previousRelease = state.current;
      await ctx.run(
        planDestroy(
          ctx,
          r,
          state.registry,
          state.registryText,
          purgeBackups: purgeBackups,
          domainSteps: e.domains.isEmpty || e.proxy.kind == ProxyKind.none
              ? const []
              : planDomain(ctx, r, [
                  for (final d in e.domains) d.host,
                ], remove: true).steps,
          scheduleSteps: e.backup == null
              ? const []
              : planSchedule(ctx, r, macos: macos, remove: true).steps,
        ),
      );
    },
  );

  // ----------------------------------------------------------------- backups

  Operation backupNow(String envName) => _op('backup now', envName, const {}, (
    ctx,
    rec,
  ) async {
    final (:state, :r) = await _load(ctx, config.env(envName));
    rec.release = state.current;
    final plan = planBackupNow(ctx, r);
    if (dryRun) return ctx.run(plan);
    ctx.log.emit(
      PlanReady(plan.title, [
        for (final s in plan.steps) s.title,
      ], plan.render()),
    );
    final step = plan.steps.single as RemoteStep;
    ctx.log.emit(StepStarted(1, 1, step.title));
    final t0 = DateTime.now();
    final code = await ctx.ssh.lines(step.host, step.script, (l, err) {
      final m = RegExp(r'PODSHIP_BACKUP_STAMP=(\S+)').firstMatch(l);
      if (m != null) rec.data['stamp'] = m[1];
      final m2 = RegExp(r'\[backup\] stamp (\S+)').firstMatch(l);
      if (m2 != null) rec.data['stamp'] ??= m2[1];
      ctx.log.output(l, stderr: err);
    });
    if (code != 0) {
      ctx.log.emit(StepFailed(1, step.title, 'exit code $code'));
      throw StepError(step, 'exit code $code');
    }
    ctx.log.emit(StepFinished(1, step.title, DateTime.now().difference(t0)));
  });

  Operation backupDrill(String envName, {String? stamp}) =>
      _op('backup drill', envName, {'stamp': stamp}, (ctx, rec) async {
        final (:state, :r) = await _load(ctx, config.env(envName));
        if (stamp != null) rec.data['stamp'] = stamp;
        await ctx.run(planDrill(ctx, r, stamp));
      });

  /// Replaces the database with a backup. The caller must have asked the
  /// user to type the project name.
  Operation backupRestore(
    String envName, {
    String? stamp,
    String? dumpFile,
    String? fromEnv,
    bool volumes = false,
  }) => _op(
    'backup restore',
    envName,
    {
      'stamp': stamp,
      'from': fromEnv,
      'volumes': volumes,
      'confirm_project': config.project,
    },
    (ctx, rec) async {
      final (:state, :r) = await _load(ctx, config.env(envName));
      rec.release = state.current;
      rec.data['stamp'] = stamp ?? dumpFile ?? 'newest';
      if (fromEnv != null) rec.data['from'] = fromEnv;
      if (volumes) rec.data['volumes'] = true;
      await ctx.run(
        planRestore(
          ctx,
          r,
          stamp: stamp,
          dumpFile: dumpFile,
          from: fromEnv == null ? null : config.env(fromEnv),
          volumes: volumes,
        ),
      );
    },
  );

  Operation backupSchedule(String envName, {bool remove = false}) =>
      _op('backup schedule', envName, {'remove': remove}, (ctx, rec) async {
        final e = config.env(envName);
        final macos =
            !dryRun && (await ctx.query(e, 'uname -s')).trim() == 'Darwin';
        final (:state, :r) = await _load(ctx, e);
        if (r.backupSchedule != null) rec.data['schedule'] = r.backupSchedule;
        rec.data['scheduler'] = macos ? 'launchd' : 'systemd';
        await ctx.run(planSchedule(ctx, r, macos: macos, remove: remove));
      });

  /// Copies the encrypted backups to this machine and checks the newest.
  Operation backupPull(String envName) => _op(
    'backup pull',
    envName,
    const {},
    (ctx, rec) async {
      await ctx.run(planPull(ctx, config.env(envName)));
    },
    history: false,
    lock: false,
  );

  // ------------------------------------------------------- variables, secrets

  Operation envSet(
    String envName,
    Map<String, String> values,
  ) => _op('env set', envName, {'values': values}, (ctx, rec) async {
    final e = config.env(envName);
    final l = EnvLayout(e);
    rec.data['names'] = values.keys.toList();
    await ctx.run(
      Plan('env set on ${e.name}', [
        ActionStep(
          'Edit ${l.envFile}',
          'set ${values.entries.map((x) => '${x.key}=${x.value}').join(' ')} (plain)',
          () async {
            final f = DotEnv(await readRemote(ctx, e, l.envFile));
            values.forEach((k, v) => f.set(k, v, plain: true));
            await writeRemote(ctx, e, l.envFile, f.toString());
          },
        ),
      ]),
    );
  });

  Operation envUnset(String envName, List<String> names) =>
      _op('env unset', envName, {'names': names}, (ctx, rec) async {
        final e = config.env(envName);
        final l = EnvLayout(e);
        rec.data['names'] = names;
        await ctx.run(
          Plan('env unset on ${e.name}', [
            editRemote(ctx, e, l.envFile, 'unset ${names.join(' ')}', (t) {
              final f = DotEnv(t);
              names.forEach(f.unset);
              return f.toString();
            }),
          ]),
        );
      });

  /// Sets a secret. [value] never appears in events or history.
  Operation secretSet(
    String envName,
    String name,
    String value, {
    bool password = false,
  }) => _op(
    'secret set',
    envName,
    {'name': name, 'value': value, 'password': password},
    (ctx, rec) async {
      final e = config.env(envName);
      final l = EnvLayout(e);
      rec.data['name'] = password ? 'password ${e.runMode}.$name' : name;
      await ctx.run(
        Plan('secret set on ${e.name}', [
          editRemote(
            ctx,
            e,
            password ? l.passwordsFile : l.envFile,
            'set ${password ? '${e.runMode}.' : ''}$name',
            (t) {
              if (password) {
                return (PasswordsFile(
                  t,
                )..set(e.runMode, name, value)).toString();
              }
              return (DotEnv(t)..set(name, value)).toString();
            },
          ),
        ]),
      );
    },
  );

  Operation secretUnset(
    String envName,
    List<String> names, {
    bool password = false,
  }) => _op('secret unset', envName, {'names': names, 'password': password}, (
    ctx,
    rec,
  ) async {
    final e = config.env(envName);
    final l = EnvLayout(e);
    rec.data['names'] = names;
    await ctx.run(
      Plan('secret unset on ${e.name}', [
        editRemote(
          ctx,
          e,
          password ? l.passwordsFile : l.envFile,
          'unset ${names.join(' ')}',
          (t) {
            if (password) {
              final f = PasswordsFile(t);
              for (final n in names) {
                f.unset(e.runMode, n);
              }
              return f.toString();
            }
            final f = DotEnv(t);
            names.forEach(f.unset);
            return f.toString();
          },
        ),
      ]),
    );
  });

  /// Copies secrets from [fromEnv] to [envName] without showing them.
  Operation secretCopy(
    String fromEnv,
    String envName,
    List<String> names, {
    bool password = false,
  }) => _op('secret copy', envName, {'from': fromEnv}, (ctx, rec) async {
    final src = config.env(fromEnv), e = config.env(envName);
    final sl = EnvLayout(src), dl = EnvLayout(e);
    rec.data['from'] = src.name;
    rec.data['names'] = names;
    await ctx.run(
      Plan('secret copy ${src.name} → ${e.name}', [
        ActionStep(
          'Copy ${names.join(', ')}',
          '${src.name} → ${e.name} (values hidden)',
          () async {
            if (password) {
              final from = PasswordsFile(
                await readRemote(ctx, src, sl.passwordsFile),
              );
              final to = PasswordsFile(
                await readRemote(ctx, e, dl.passwordsFile),
              );
              for (final n in names) {
                final v = from.get(src.runMode, n) ?? from.get('shared', n);
                if (v == null) throw Aborted('${src.name} has no password $n');
                to.set(e.runMode, n, v);
              }
              await writeRemote(ctx, e, dl.passwordsFile, to.toString());
            } else {
              final from = DotEnv(await readRemote(ctx, src, sl.envFile));
              final to = DotEnv(await readRemote(ctx, e, dl.envFile));
              for (final n in names) {
                final v = from.get(n);
                if (v == null) throw Aborted('${src.name} has no $n');
                to.set(n, v);
              }
              await writeRemote(ctx, e, dl.envFile, to.toString());
            }
          },
        ),
      ]),
    );
  });

  /// Copies every variable of `.env` and every `passwords.yaml` key of the
  /// run-mode section from [fromEnv] to [envName], except [except]. Values
  /// pass through memory only. Use it to move an environment to another
  /// server with the same secrets (the same master key, for example).
  Operation secretCopyAll(
    String fromEnv,
    String envName, {
    List<String> except = const [],
  }) => _op('secret copy', envName, {'from': fromEnv}, (ctx, rec) async {
    final src = config.env(fromEnv), e = config.env(envName);
    final sl = EnvLayout(src), dl = EnvLayout(e);
    rec.data['from'] = src.name;
    rec.data['all'] = true;
    rec.data['except'] = except;
    await ctx.run(
      Plan('secret copy ${src.name} → ${e.name} (all)', [
        ActionStep(
          'Copy every variable and password',
          '${src.name} → ${e.name}, except ${except.isEmpty ? 'none' : except.join(', ')} (values hidden)',
          () async {
            final from = DotEnv(await readRemote(ctx, src, sl.envFile));
            final to = DotEnv(await readRemote(ctx, e, dl.envFile));
            final names = <String>[];
            for (final n in from.names) {
              if (except.contains(n)) continue;
              to.set(n, from.get(n)!, plain: isPlain(src, from, n));
              names.add(n);
            }
            await writeRemote(ctx, e, dl.envFile, to.toString());
            final pf = PasswordsFile(
              await readRemote(ctx, src, sl.passwordsFile),
            );
            final pt = PasswordsFile(
              await readRemote(ctx, e, dl.passwordsFile),
            );
            final keys = <String>[];
            for (final section in pf.sections) {
              for (final k in pf.keys(section)) {
                pt.set(section, k, pf.get(section, k)!);
                keys.add('$section.$k');
              }
            }
            await writeRemote(ctx, e, dl.passwordsFile, pt.toString());
            rec.data['names'] = names;
            rec.data['password_keys'] = keys;
            ctx.log.info(
              'copied ${names.length} variables and ${keys.length} passwords',
            );
          },
        ),
      ]),
    );
  });

  Operation secretInit(String envName, {bool force = false}) =>
      _op('secret init', envName, {'force': force}, (ctx, rec) async {
        await ctx.run(planSecretInit(ctx, config.env(envName), force: force));
      });

  // ------------------------------------------------------- domains, server, db

  Operation domainAdd(String envName, {List<String>? hosts}) =>
      _domain(envName, hosts, remove: false);
  Operation domainRemove(String envName, {List<String>? hosts}) =>
      _domain(envName, hosts, remove: true);

  Operation _domain(
    String envName,
    List<String>? hosts, {
    required bool remove,
  }) => _op(
    remove ? 'domain remove' : 'domain add',
    envName,
    {'hosts': hosts},
    (ctx, rec) async {
      final e = config.env(envName);
      final list = hosts == null || hosts.isEmpty
          ? [for (final d in e.domains) d.host]
          : hosts;
      if (list.isEmpty) {
        throw Aborted('no domains in environments.${e.name}.domains');
      }
      final (:state, :r) = await _load(ctx, e);
      rec.data['hosts'] = list;
      await ctx.run(planDomain(ctx, r, list, remove: remove));
      if (!remove) {
        rec.data['dns'] = {for (final h in list) h: dnsRecord(e, h)};
        for (final h in list) {
          ctx.log.info('DNS for $h: ${dnsRecord(e, h)}');
        }
      }
    },
  );

  Operation bootstrap(
    String envName, {
    bool caddy = false,
    bool firewall = true,
    String? user,
  }) => _op('server bootstrap', envName, {'caddy': caddy}, (ctx, rec) async {
    final e = config.env(envName);
    await ctx.run(
      Plan('bootstrap ${e.host}', [
        RemoteStep(
          'Install what is missing',
          e.host,
          bootstrapScript(
            e,
            caddy: caddy || e.proxy.kind == ProxyKind.caddy,
            firewall: firewall,
            deployUser: user,
          ),
        ),
      ]),
    );
  });

  Operation dbProvision(
    String envName,
  ) => _op('db provision', envName, const {}, (ctx, rec) async {
    final e = config.env(envName);
    if (e.database.mode != DatabaseMode.shared) {
      throw Aborted(
        '${e.name} uses its own Postgres (database.mode: per_env); nothing to provision',
      );
    }
    final l = EnvLayout(e);
    await ctx.run(
      Plan('provision ${e.database.name} in the shared Postgres on ${e.host}', [
        ActionStep(
          'Create database and role',
          '${e.database.name} owned by ${e.database.user}; password stored as a secret (hidden)',
          () async {
            final out = await ctx.query(e, sharedDbScript(e));
            final pw = RegExp(
              r'PODSHIP_DB_PASSWORD=(\S+)',
            ).firstMatch(out)![1]!;
            final pf = PasswordsFile(await readRemote(ctx, e, l.passwordsFile))
              ..set(e.runMode, 'database', pw);
            await writeRemote(ctx, e, l.passwordsFile, pf.toString());
            final f = DotEnv(await readRemote(ctx, e, l.envFile))
              ..set(
                'SERVERPOD_DATABASE_HOST',
                DatabaseConfig.sharedContainer,
                plain: true,
              )
              ..set('SERVERPOD_DATABASE_PORT', '5432', plain: true)
              ..set('SERVERPOD_DATABASE_NAME', e.database.name, plain: true)
              ..set('SERVERPOD_DATABASE_USER', e.database.user, plain: true)
              ..set('SERVERPOD_DATABASE_REQUIRE_SSL', 'false', plain: true);
            await writeRemote(ctx, e, l.envFile, f.toString());
          },
        ),
      ]),
    );
  });

  /// An empty database; the old one is renamed. The caller must have asked
  /// the user to type the project name.
  Operation dbWipe(String envName) => _op(
    'db wipe',
    envName,
    {'confirm_project': config.project},
    (ctx, rec) async {
      final e = config.env(envName);
      final l = EnvLayout(e);
      final db = e.database.name;
      await ctx.run(
        Plan('db wipe ${e.name}', [
          RemoteStep('Rename $db and create an empty one', e.host, '''
${ctx.header(e)}c=${dbContainerExpr(e)}
${shq(l.currentComposeSh)} stop ${shq(e.serverService)}
docker exec -i "\$c" psql -U ${shq(dbAdmin(e))} -d postgres -v ON_ERROR_STOP=1 \\
  -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$db' and pid <> pg_backend_pid();" \\
  -c "alter database \\"$db\\" rename to \\"${db}_wiped_\$(date +%Y%m%d%H%M%S)\\";" \\
  -c "create database \\"$db\\";"
${shq(l.currentComposeSh)} up -d --no-build ${shq(e.serverService)}
'''),
        ]),
      );
    },
  );

  /// Creates, resets or deletes a database role. On create and reset, the
  /// password is in `result.data['password']`, once, and not in history.
  Operation dbUser(
    String envName,
    String action,
    String role,
  ) => _op('db user $action', envName, {'role': role}, (ctx, rec) async {
    final e = config.env(envName);
    if (!RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch(role)) {
      throw Aborted('invalid role name');
    }
    final pw = randomSecret(24).replaceAll(RegExp(r'[^A-Za-z0-9]'), 'x');
    final db = e.database.name;
    final q = switch (action) {
      'create' =>
        'create role "$role" login password \'$pw\';\n'
            'grant connect on database "$db" to "$role";\n'
            'grant usage on schema public to "$role";\n'
            'grant select, insert, update, delete on all tables in schema public to "$role";\n'
            'grant usage, select on all sequences in schema public to "$role";\n'
            'alter default privileges in schema public grant select, insert, update, delete on tables to "$role";\n',
      'reset-password' => 'alter role "$role" password \'$pw\';\n',
      'delete' =>
        'reassign owned by "$role" to "${dbAdmin(e)}"; drop owned by "$role"; drop role "$role";\n',
      _ => throw Aborted('unknown action $action'),
    };
    rec.data['role'] = role;
    await ctx.run(
      Plan('db user $action $role on ${e.name}', [
        ActionStep(
          'Run SQL',
          'db user $action $role (password hidden)',
          () async {
            await sql(ctx, e, q);
            if (action != 'delete') {
              rec.data['password'] = pw;
              rec.sensitive.add('password');
            }
          },
        ),
      ]),
    );
  });

  /// Adds or removes a person's ssh key on the server.
  Operation access(
    String envName,
    String action,
    String who, {
    String? publicKey,
  }) => _op('access $action', envName, {'name': who}, (ctx, rec) async {
    final e = config.env(envName);
    if (!RegExp(r'^[A-Za-z0-9._@-]+$').hasMatch(who)) {
      throw Aborted('invalid name');
    }
    rec.data['name'] = who;
    String script;
    if (action == 'add') {
      final key = (publicKey ?? '').trim().split('\n').first;
      final parts = key.split(RegExp(r'\s+'));
      if (parts.length < 2 || !isPublicKey(key)) {
        throw Aborted('not a public key');
      }
      final line = '${parts[0]} ${parts[1]} podship:$who';
      script =
          '''
umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys
grep -v ${shq(' podship:$who\$')} ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.podship-tmp || true
echo ${shq(line)} >> ~/.ssh/authorized_keys.podship-tmp
mv -f ~/.ssh/authorized_keys.podship-tmp ~/.ssh/authorized_keys
echo "added $who"
''';
    } else {
      script =
          '''
grep -v ${shq(' podship:$who\$')} ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.podship-tmp || true
mv -f ~/.ssh/authorized_keys.podship-tmp ~/.ssh/authorized_keys
echo "removed $who"
''';
    }
    await ctx.run(
      Plan('access $action $who on ${e.host}', [
        RemoteStep('Edit ~/.ssh/authorized_keys', e.host, script),
      ]),
    );
  });

  /// Creates a server at [provider] (it costs money: the caller must have
  /// the user's go-ahead), waits until it answers, and bootstraps it over
  /// ssh as root. The provider token comes from the secret store
  /// (`podship provider login <name>`).
  Operation serverCreate(
    String provider,
    ServerSpec spec, {
    bool bootstrap = true,
  }) => _op('server create', null, {'provider': provider, ...spec.toJson()}, (
    ctx,
    rec,
  ) async {
    registerBuiltInProviders();
    rec.data['provider'] = provider;
    if (dryRun) {
      ctx.log.emit(
        PlanReady('create ${spec.name} at $provider', [
          'Create',
          'Wait',
          'Bootstrap',
        ], describeCreate(provider, spec)),
      );
      return;
    }
    final token = TokenStore().read('provider:$provider');
    if (token == null) {
      throw Aborted(
        'no $provider token: run `podship provider login $provider`',
      );
    }
    final p = providerFor(provider, token);
    ctx.log.emit(
      StepStarted(1, 3, 'Create ${spec.name} in ${spec.region} (${spec.plan})'),
    );
    final created = await p.create(spec);
    rec.data['server'] = created.toJson();
    ctx.log.emit(StepStarted(2, 3, 'Wait until it answers'));
    final ready = await p.waitReady(created.id);
    rec.data['server'] = ready.toJson();
    final ip = ready.ipv4 ?? ready.ipv6!;
    ctx.log.info('${spec.name}: ${ready.ipv4 ?? ''} ${ready.ipv6 ?? ''}');
    if (bootstrap) {
      ctx.log.emit(StepStarted(3, 3, 'Bootstrap'));
      final host = 'root@${ip.contains(':') ? '[$ip]' : ip}';
      final e = EnvConfig(
        name: 'new',
        host: 'root@$ip',
        dir: '/srv/podship-new',
        composeProject: 'podship-new',
        health: HealthConfig(url: 'http://127.0.0.1/'),
      );
      for (var i = 0; i < 30; i++) {
        final r = await ctx.ssh.captureResult(e.host, 'true');
        if (r.exitCode == 0) break;
        await Future<void>.delayed(const Duration(seconds: 10));
      }
      await ctx.run(
        Plan('bootstrap $host', [
          RemoteStep('Install what is missing', e.host, bootstrapScript(e)),
        ]),
      );
    }
    ctx.log.info(
      'Add it to ~/.ssh/config as a Host alias, then use it as `host:` in podship.yaml.',
    );
  }, lock: false);

  /// Deletes a server at [provider]. The caller must have asked the user to
  /// type the server's name.
  Operation serverDestroy(String provider, String id) => _op(
    'server destroy',
    null,
    {'provider': provider, 'id': id},
    (ctx, rec) async {
      registerBuiltInProviders();
      if (dryRun) {
        ctx.log.info('would delete $provider server $id');
        return;
      }
      final token = TokenStore().read('provider:$provider');
      if (token == null) {
        throw Aborted(
          'no $provider token: run `podship provider login $provider`',
        );
      }
      rec.data['result'] = await providerFor(provider, token).destroy(id);
      ctx.log.info('${rec.data['result']}');
    },
    lock: false,
  );

  /// Changes the number of server containers of the current release
  /// (monolith + serverless replicas behind podship's load balancer).
  Operation scale(String envName, int replicas) =>
      _op('scale', envName, {'replicas': replicas}, (ctx, rec) async {
        final e = config.env(envName);
        final l = EnvLayout(e);
        final (:state, :r) = await _load(ctx, e);
        rec.release = state.current;
        rec.data['replicas'] = replicas;
        await ctx.run(
          Plan('scale ${e.name} to $replicas server containers', [
            RemoteStep(
              'Scale ${e.serverService}-replica to ${replicas - 1}',
              e.host,
              '''
${ctx.header(e)}grep -q '"${e.serverService}-replica"' ${shq('${l.current}/.podship/override.yml')} || { echo "the current release has no replicas: set serverpod.replicas in podship.yaml and deploy" >&2; exit 1; }
${shq(l.currentComposeSh)} up -d --no-build --no-recreate --scale ${shq('${e.serverService}-replica=${replicas - 1}')}
${shq(l.currentComposeSh)} restart podship-lb
''',
            ),
            HealthStep(
              'Health check',
              e.host,
              r.healthUrls,
              attempts: e.health.attempts,
              intervalSeconds: e.health.intervalSeconds,
            ),
          ]),
        );
      });

  /// Load test: k6 in a container on the environment's server sends [vus]
  /// virtual users at [path] on the [port] port for [duration] (like
  /// `30s`), and prints latency and errors. On production it competes with
  /// real users: run it on staging first.
  Operation loadtest(
    String envName, {
    String path = '/health',
    int vus = 10,
    String duration = '30s',
    String port = 'web',
  }) => _op(
    'loadtest',
    envName,
    {'path': path, 'vus': vus, 'duration': duration, 'port': port},
    (ctx, rec) async {
      final e = config.env(envName);
      final (:state, :r) = await _load(ctx, e);
      final p =
          r.ports[port] ?? (throw Aborted('no port "$port" in ${e.name}'));
      final script = [
        "import http from 'k6/http';",
        "import { check } from 'k6';",
        "export const options = { vus: $vus, duration: '$duration', thresholds: { http_req_failed: ['rate<0.01'] } };",
        'export default function () {',
        "  const res = http.get(__ENV.TARGET + '$path');",
        "  check(res, { 'status is 2xx': (r) => r.status >= 200 && r.status < 300 });",
        '}',
      ].join('\n');
      final remote =
          'if [ "\$(uname -s)" = Darwin ]; then net=""; target="http://host.docker.internal:$p"; '
          'else net="--network host"; target="http://127.0.0.1:$p"; fi\n'
          '${writeFile('/tmp/podship-k6.js', script)}'
          'docker run --rm -i \$net -e TARGET="\$target" -v /tmp/podship-k6.js:/k6.js:ro grafana/k6:latest run --quiet /k6.js\n'
          'rm -f /tmp/podship-k6.js\n';
      await ctx.run(
        Plan('load test ${e.name}: $vus users on $path for $duration', [
          RemoteStep('k6 against port $p$path', e.host, ctx.header(e) + remote),
        ]),
      );
    },
    lock: false,
  );

  /// Removes the lock of [envName], for a lock left by a client that died.
  Operation unlock(String envName) => _op('unlock', envName, const {}, (
    ctx,
    rec,
  ) async {
    final e = config.env(envName);
    final held = await readLock(ctx, e);
    rec.data['was'] = held;
    if (held == null) {
      ctx.log.info('${e.name} is not locked');
      return;
    }
    if (!dryRun) await releaseLock(ctx, e);
    ctx.log.info('removed the lock of ${held['actor']} (${held['operation']})');
  }, lock: false);

  /// Who holds the lock of [envName], or null.
  Future<Map<String, Object?>?> lockHolder(String envName) =>
      readLock(_readCtx, config.env(envName));

  // ------------------------------------------------------------------- reads

  /// The current release, the releases, containers, health and disk.
  Future<EnvStatus> status(String envName) async {
    final ctx = _readCtx;
    final e = config.env(envName);
    final (:state, :r) = await _load(ctx, e);
    final l = EnvLayout(e);
    final out = await ctx.query(e, '''
if [ -x ${shq(l.currentComposeSh)} ]; then
  ${shq(l.currentComposeSh)} ps --all --format json 2>/dev/null | sed 's/^/PS /' || true
fi
if curl -fs -o /dev/null --max-time 5 ${shq(r.healthUrl)}; then echo "HEALTH ok"; else echo "HEALTH failing"; fi
df -Pk ${shq(e.dir)} 2>/dev/null | tail -1 | awk '{print "DISK " \$4 " " \$2}'
du -sk ${shq(l.releases)} 2>/dev/null | awk '{print "RELEASES_KB " \$1}'
''');
    final st = EnvStatus.parse(
      project: config.project,
      env: e.name,
      host: e.host,
      dir: e.dir,
      state: state,
      ports: r.ports,
      healthUrl: r.healthUrl,
      output: out,
    );
    var logs = <String, Map<String, int>>{};
    try {
      final out = await sql(
        ctx,
        e,
        "select relname, coalesce(n_live_tup, 0), pg_total_relation_size(relid) from pg_stat_user_tables where relname in ('serverpod_session_log', 'serverpod_log', 'serverpod_query_log', 'serverpod_message_log') order by 1;",
      );
      logs = {
        for (final l in const LineSplitter().convert(out))
          if (l.split(' | ').length == 3)
            l.split(' | ')[0]: {
              'rows': int.parse(l.split(' | ')[1]),
              'bytes': int.parse(l.split(' | ')[2]),
            },
      };
    } catch (_) {}
    return st.withLogTables(logs);
  }

  Future<List<ReleaseInfo>> releases(String envName) async => (await fetchState(
    _readCtx,
    config.env(envName),
  )).releases.reversed.toList();

  /// What runs where: every environment's current release, its commit,
  /// and the previous releases with who made them and when. Environments
  /// whose server does not answer have an `error`.
  Future<List<Map<String, Object?>>> overview() async {
    final out = <Map<String, Object?>>[];
    for (final e in config.environments.values) {
      try {
        final st = await fetchState(_readCtx, e);
        out.add({
          'env': e.name,
          'host': e.host,
          'current': st.current,
          'current_sha': _shaOf(st, st.current),
          'releases': [
            for (final r in st.releases.reversed) r.toJson(current: st.current),
          ],
        });
      } catch (x) {
        out.add({'env': e.name, 'host': e.host, 'error': '$x'});
      }
    }
    return out;
  }

  /// Which environments run a release that contains commit [sha] (by git
  /// ancestry, in the local repository).
  Future<List<Map<String, Object?>>> releasesContaining(String sha) async {
    final full = await Process.run('git', [
      'rev-parse',
      sha,
    ], workingDirectory: config.root);
    if (full.exitCode != 0) throw Aborted('unknown commit $sha');
    final target = (full.stdout as String).trim();
    final out = <Map<String, Object?>>[];
    for (final o in await overview()) {
      final cur = o['current_sha'] as String?;
      bool? contains;
      if (cur != null) {
        final r = await Process.run('git', [
          'merge-base',
          '--is-ancestor',
          target,
          cur,
        ], workingDirectory: config.root);
        contains = r.exitCode == 0 ? true : (r.exitCode == 1 ? false : null);
      }
      out.add({
        'env': o['env'],
        'current': o['current'],
        'current_sha': cur,
        'contains': contains,
        if (o['error'] != null) 'error': o['error'],
      });
    }
    return out;
  }

  Future<String?> currentRelease(String envName) async =>
      (await fetchState(_readCtx, config.env(envName))).current;

  Future<List<BackupInfo>> backups(String envName) async {
    final ctx = _readCtx;
    final e = config.env(envName);
    final (:state, :r) = await _load(ctx, e);
    final out = await ctx.query(
      e,
      '${backupSetup(config, r)}${shq('${e.libDir}/backup.sh')} ${shq(backupConfPath(e))} --list',
    );
    return [
      for (final line in const LineSplitter().convert(out))
        if (line.trim().split(' ').length == 3) BackupInfo.parse(line),
    ];
  }

  Future<List<EnvVarInfo>> envList(String envName) async {
    final e = config.env(envName);
    final f = DotEnv(await readRemote(_readCtx, e, EnvLayout(e).envFile));
    return [
      for (final n in f.names)
        isPlain(e, f, n)
            ? EnvVarInfo(n, secret: false, value: f.get(n))
            : EnvVarInfo(n, secret: true),
    ];
  }

  /// A plain variable's value. Throws [Aborted] for a secret.
  Future<String> envGet(String envName, String name) async {
    final e = config.env(envName);
    final f = DotEnv(await readRemote(_readCtx, e, EnvLayout(e).envFile));
    if (!f.has(name)) throw Aborted('$name is not set in ${e.name}');
    if (!isPlain(e, f, name)) {
      throw Aborted('$name is a secret; podship never prints secret values');
    }
    return f.get(name)!;
  }

  /// Secret names: `.env` secrets, then `password <section>.<key>`.
  Future<List<String>> secretList(String envName) async {
    final e = config.env(envName);
    final l = EnvLayout(e);
    final f = DotEnv(await readRemote(_readCtx, e, l.envFile));
    final pw = PasswordsFile(await readRemote(_readCtx, e, l.passwordsFile));
    return [
      for (final n in f.names)
        if (!isPlain(e, f, n)) n,
      for (final s in pw.sections)
        for (final k in pw.keys(s)) 'password $s.$k',
    ];
  }

  /// The registry of the server of [envName].
  Future<Registry> projects(String envName) async =>
      (await fetchState(_readCtx, config.env(envName))).registry;

  /// Every project, container and the disk of the server of [envName].
  Future<ServerStatus> serverStatus(String envName) async {
    final e = config.env(envName);
    final ctx = _readCtx;
    final state = await fetchState(ctx, e);
    final out = await ctx.query(e, r'''
docker stats --no-stream --format '{{json .}}' | sed 's/^/STAT /'
docker ps --format '{{json .}}' | sed 's/^/PS /'
df -Pk / | tail -1 | awk '{print "DISK " $4 " " $2}'
''');
    return ServerStatus.parse(e.host, state.registry, out);
  }

  Future<List<DomainInfo>> domains(String envName) async {
    final e = config.env(envName);
    final ctx = _readCtx;
    final (:state, :r) = await _load(ctx, e);
    final rules =
        e.proxy.kind == ProxyKind.cloudflareTunnel && e.proxy.config != null
        ? tunnelRules(await readRemote(ctx, e, e.proxy.config!))
        : const <String>[];
    final out = <DomainInfo>[];
    for (final d in r.domains.entries) {
      List<String> addrs = const [];
      try {
        addrs = [
          for (final a in await InternetAddress.lookup(d.key)) a.address,
        ];
      } catch (_) {}
      out.add(
        DomainInfo(
          host: d.key,
          routes: [for (final x in d.value) '${x.path ?? '/'} → ${x.port}'],
          dnsAnswers: addrs,
          dnsNeeded: dnsRecord(e, d.key),
          proxyRules: [
            for (final x in rules)
              if (x.startsWith('${d.key} ')) x,
          ],
        ),
      );
    }
    return out;
  }

  Future<MigrationStatus> migrateStatus(String envName) async {
    final e = config.env(envName);
    final ctx = _readCtx;
    final l = EnvLayout(e);
    final applied = await sql(
      ctx,
      e,
      'select module, version, "timestamp" from serverpod_migrations order by module;',
    );
    final shipped = await ctx.query(
      e,
      'ls -1 ${shq('${l.current}/${config.serverPackage}/migrations')} 2>/dev/null | grep -E "^[0-9]{17}" | sort | tail -1 || true',
    );
    return MigrationStatus.parse(applied, shipped.trim(), config.serverPackage);
  }

  /// History records of [envName], newest last. With [allProjects], every
  /// project and environment on that server.
  Future<List<HistoryRecord>> history(
    String envName, {
    int limit = 20,
    bool allProjects = false,
  }) => readHistory(
    _readCtx,
    config.env(envName),
    config.project,
    limit: limit,
    allProjects: allProjects,
  );

  /// Log lines of the current release. With [follow], the stream stays
  /// open until cancelled.
  Stream<String> logs(
    String envName, {
    List<String> services = const [],
    String? since,
    String? until,
    int tail = 100,
    bool follow = false,
    bool timestamps = false,
  }) {
    final e = config.env(envName);
    final l = EnvLayout(e);
    final ctx = _readCtx;
    final cmd = [
      shq(l.currentComposeSh),
      'logs',
      '--no-color',
      '--tail',
      '$tail',
      if (since != null) ...['--since', shq(since)],
      if (until != null) ...['--until', shq(until)],
      if (follow) '--follow',
      if (timestamps) '--timestamps',
      ...services.map(shq),
    ].join(' ');
    final c = StreamController<String>();
    Process? proc;
    c.onListen = () async {
      proc = await Process.start('ssh', [
        ...ctx.ssh.options(),
        e.host,
        'bash -c ${shq(ctx.header(e) + cmd)}',
      ]);
      final a = proc!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(c.add);
      final b = proc!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(c.add);
      await Future.wait([a, b]);
      await proc!.exitCode;
      await c.close();
    };
    c.onCancel = () => proc?.kill();
    return c.stream;
  }

  /// Where the server keeps history records for this project.
  String historyDir(String envName) {
    final e = config.env(envName);
    return p.posix.join(e.podshipHome, 'history', config.project, e.name);
  }
}
