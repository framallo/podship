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
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../server/registry.dart';
import '../util/log.dart';
import 'events.dart';
import 'history.dart';
import 'render.dart';
import 'models.dart';

export '../ops/deploy.dart' show DeployOptions;
export '../ops/state.dart' show ReleaseInfo;

/// The package version, written into history records.
const podshipVersion = '0.2.0';

/// A running operation: its events, and its result when it ends.
class Operation {
  Operation(this.events, this.result);

  /// Every event, from [OperationStarted] to [OperationFinished]. A single
  /// listener; events are kept until someone listens.
  final Stream<PodshipEvent> events;

  /// The result. It completes after the last event, and never throws: a
  /// failure is a result with `ok: false`.
  final Future<OperationResult> result;
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
    Future<void> Function(Ctx ctx, OpRecord rec) body, {
    bool history = true,
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
      try {
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

    return Operation(events.stream, run());
  }

  // ---------------------------------------------------------------- releases

  /// Builds and starts a new release; rolls back if it is not healthy.
  Operation deploy(
    String envName, {
    DeployOptions options = const DeployOptions(),
    String? ref,
  }) => _op('deploy', envName, (ctx, rec) async {
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
        options: options,
      );
      final id = plan.title.split(' as ').last;
      rec.data['sha'] = git.sha;
      await ctx.run(plan).catchError((Object x) async {
        // The recovery may have switched back; report what runs now.
        rec.release = (await fetchState(_readCtx, e)).current;
        throw x;
      });
      rec.release = dryRun ? state.current : id;
      rec.data['new_release'] = id;
    } finally {
      await snap.delete(recursive: true);
    }
  });

  /// Switches to a previous release (code only), or to [to]. With [withDb],
  /// restores that backup first.
  Operation rollback(String envName, {String? to, String? withDb}) =>
      _op('rollback', envName, (ctx, rec) async {
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
        } catch (_) {
          rec.release = (await fetchState(_readCtx, e)).current;
          rethrow;
        }
      });

  /// Recreates the containers of the current release.
  Operation restart(String envName, {List<String> services = const []}) =>
      _op('restart', envName, (ctx, rec) async {
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
  }) => _op('promote', toEnv, (ctx, rec) async {
    final from = config.env(fromEnv), to = config.env(toEnv);
    final fromState = await fetchState(ctx, from);
    final id = release ?? fromState.current;
    if (id == null) throw Aborted('nothing runs on ${from.name}');
    final (:state, :r) = await _load(ctx, to);
    rec.previousRelease = state.current;
    rec.data['from'] = from.name;
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
    } catch (_) {
      rec.release = (await fetchState(_readCtx, to)).current;
      rethrow;
    } finally {
      await work.delete(recursive: true);
    }
  });

  /// Records a setup that runs already as a release, without restarting it.
  Operation adopt(String envName, {String? composeDir}) =>
      _op('adopt', envName, (ctx, rec) async {
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
  Operation link(String envName) => _op('link', envName, (ctx, rec) async {
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
  Operation destroy(String envName, {bool purgeBackups = false}) =>
      _op('destroy', envName, (ctx, rec) async {
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
      });

  // ----------------------------------------------------------------- backups

  Operation backupNow(String envName) => _op('backup now', envName, (
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
      _op('backup drill', envName, (ctx, rec) async {
        final (:state, :r) = await _load(ctx, config.env(envName));
        if (stamp != null) rec.data['stamp'] = stamp;
        await ctx.run(planDrill(ctx, r, stamp));
      });

  /// Replaces the database with a backup. The caller must have asked the
  /// user to type the project name.
  Operation backupRestore(String envName, {String? stamp, String? dumpFile}) =>
      _op('backup restore', envName, (ctx, rec) async {
        final (:state, :r) = await _load(ctx, config.env(envName));
        rec.release = state.current;
        rec.data['stamp'] = stamp ?? dumpFile ?? 'newest';
        await ctx.run(planRestore(ctx, r, stamp: stamp, dumpFile: dumpFile));
      });

  Operation backupSchedule(String envName, {bool remove = false}) =>
      _op('backup schedule', envName, (ctx, rec) async {
        final e = config.env(envName);
        final macos =
            !dryRun && (await ctx.query(e, 'uname -s')).trim() == 'Darwin';
        final (:state, :r) = await _load(ctx, e);
        if (r.backupSchedule != null) rec.data['schedule'] = r.backupSchedule;
        rec.data['scheduler'] = macos ? 'launchd' : 'systemd';
        await ctx.run(planSchedule(ctx, r, macos: macos, remove: remove));
      });

  /// Copies the encrypted backups to this machine and checks the newest.
  Operation backupPull(String envName) =>
      _op('backup pull', envName, (ctx, rec) async {
        await ctx.run(planPull(ctx, config.env(envName)));
      }, history: false);

  // ------------------------------------------------------- variables, secrets

  Operation envSet(
    String envName,
    Map<String, String> values,
  ) => _op('env set', envName, (ctx, rec) async {
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
      _op('env unset', envName, (ctx, rec) async {
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
  }) => _op('secret set', envName, (ctx, rec) async {
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
              return (PasswordsFile(t)..set(e.runMode, name, value)).toString();
            }
            return (DotEnv(t)..set(name, value)).toString();
          },
        ),
      ]),
    );
  });

  Operation secretUnset(
    String envName,
    List<String> names, {
    bool password = false,
  }) => _op('secret unset', envName, (ctx, rec) async {
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
  }) => _op('secret copy', envName, (ctx, rec) async {
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

  Operation secretInit(String envName, {bool force = false}) =>
      _op('secret init', envName, (ctx, rec) async {
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
  }) => _op(remove ? 'domain remove' : 'domain add', envName, (ctx, rec) async {
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
  });

  Operation bootstrap(
    String envName, {
    bool caddy = false,
    bool firewall = true,
    String? user,
  }) => _op('server bootstrap', envName, (ctx, rec) async {
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

  Operation dbProvision(String envName) => _op('db provision', envName, (
    ctx,
    rec,
  ) async {
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
  Operation dbWipe(String envName) => _op('db wipe', envName, (ctx, rec) async {
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
  });

  /// Creates, resets or deletes a database role. On create and reset, the
  /// password is in `result.data['password']`, once, and not in history.
  Operation dbUser(
    String envName,
    String action,
    String role,
  ) => _op('db user $action', envName, (ctx, rec) async {
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
  }) => _op('access $action', envName, (ctx, rec) async {
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
    return EnvStatus.parse(
      project: config.project,
      env: e.name,
      host: e.host,
      dir: e.dir,
      state: state,
      ports: r.ports,
      healthUrl: r.healthUrl,
      output: out,
    );
  }

  Future<List<ReleaseInfo>> releases(String envName) async => (await fetchState(
    _readCtx,
    config.env(envName),
  )).releases.reversed.toList();

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
