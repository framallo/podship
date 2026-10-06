// deploy, rollback, promote, adopt, restart, status, logs, releases.

import 'dart:io';

import '../config/config.dart';
import '../ops/context.dart';
import '../ops/deploy.dart';
import '../ops/release_ops.dart';
import '../ops/state.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import 'base.dart';

class DeployCommand extends PodshipCommand {
  DeployCommand() {
    argParser
      ..addOption('ref', help: 'The git ref to deploy (default: build.ref).')
      ..addFlag(
        'worktree',
        negatable: false,
        help: 'Ship the working tree, uncommitted changes included.',
      )
      ..addFlag('skip-web', negatable: false, help: 'Do not build Flutter web.')
      ..addFlag(
        'skip-backup',
        negatable: false,
        help: 'No database backup before the switch.',
      )
      ..addFlag('skip-hooks', negatable: false, help: 'No pre/post hooks.')
      ..addFlag(
        'public-check',
        defaultsTo: true,
        help:
            'Also check the public health URL (turn off before the domain is routed).',
      );
  }
  @override
  String get name => 'deploy';
  @override
  String get description =>
      'Build, upload and start a new release; roll back if it is not healthy.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;

  @override
  Future<int> execute() async {
    final e = guardedEnv;
    final source = argResults!['worktree'] == true
        ? SourceMode.worktree
        : config.build.source;
    final ref = argResults!['ref'] as String? ?? config.build.ref;
    final git = await GitInfo.read(config.root, ref);
    if (source == SourceMode.git && git.sha == 'nogit') {
      throw Aborted('ref "$ref" not found; use --worktree outside git');
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
    if (e.isProduction &&
        !ctx.confirm(
          'Deploy ${git.sha.length > 7 ? git.sha.substring(0, 7) : git.sha} to PRODUCTION on ${e.host}?',
        )) {
      throw Aborted('cancelled');
    }
    final (:state, :r) = await load(e);
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
          source: source,
          skipWeb: argResults!['skip-web'] == true,
          skipBackup: argResults!['skip-backup'] == true,
          skipHooks: argResults!['skip-hooks'] == true,
          publicCheck: argResults!['public-check'] == true,
        ),
      );
      await ctx.run(plan);
      return 0;
    } finally {
      await snap.delete(recursive: true);
    }
  }
}

class RollbackCommand extends PodshipCommand {
  RollbackCommand() {
    argParser
      ..addOption(
        'to',
        help: 'The release to switch to (default: the previous one).',
      )
      ..addOption(
        'with-db',
        help: 'Also restore this database backup (a stamp from `backup list`).',
      )
      ..addOption(
        'confirm',
        help: 'The project name, to confirm --with-db without a terminal.',
      );
  }
  @override
  String get name => 'rollback';
  @override
  String get description =>
      'Switch to a previous release. Code only, unless --with-db is given.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;

  @override
  Future<int> execute() async {
    final e = guardedEnv;
    final (:state, :r) = await load(e);
    final withDb = argResults!['with-db'] as String?;
    if (withDb != null) {
      if (e.backup == null) throw Aborted('${e.name} has no backup settings');
      ctx.typeProjectName(
        'This replaces the ${e.name} database with backup $withDb (the current one is renamed, not dropped).',
        typed: argResults!['confirm'] as String?,
      );
    } else if (e.isProduction &&
        !ctx.confirm('Roll back PRODUCTION (code only)?')) {
      throw Aborted('cancelled');
    }
    await ctx.run(
      planRollback(
        ctx: ctx,
        r: r,
        state: state,
        to: argResults!['to'] as String?,
        withDb: withDb,
      ),
    );
    return 0;
  }
}

class RestartCommand extends PodshipCommand {
  @override
  String get name => 'restart';
  @override
  String get description =>
      'Recreate the containers of the current release (after env or secret changes).';
  @override
  String get invocation => '$exe restart [--env <env>] [service…]';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    final (:state, :r) = await load(e);
    await ctx.run(
      planRestart(ctx: ctx, r: r, state: state, services: argResults!.rest),
    );
    return 0;
  }
}

class PromoteCommand extends PodshipCommand {
  PromoteCommand() {
    argParser.addOption(
      'release',
      help: 'The release to promote (default: the one running on <from>).',
    );
  }
  @override
  String get name => 'promote';
  @override
  String get description =>
      'Run on <to> the exact release that runs on <from>: same files, same images.';
  @override
  String get invocation => '$exe promote <from> <to>';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;

  @override
  Future<int> execute() async {
    final rest = argResults!.rest;
    if (rest.length != 2) usageException('give two environments: <from> <to>');
    final from = config.env(rest[0]), to = config.env(rest[1]);
    if (to.isProduction &&
        !ctx.confirm('Promote ${from.name} to PRODUCTION on ${to.host}?')) {
      throw Aborted('cancelled');
    }
    final fromState = await fetchState(ctx, from);
    final release = argResults!['release'] as String? ?? fromState.current;
    if (release == null) throw Aborted('nothing runs on ${from.name}');
    final (:state, :r) = await load(to);
    if (from.host != to.host) {
      final a = await _arch(from), b = await _arch(to);
      if (a != b) {
        throw Aborted(
          '${from.name} ($a) and ${to.name} ($b) have different CPU architectures, '
          'so images cannot move. Deploy the same commit instead: '
          '$exe deploy --env ${to.name} --ref ${fromState.releases.firstWhere((x) => x.id == release).meta?.sha ?? release}',
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
          release: release,
          workDir: work.path,
        ),
      );
    } finally {
      await work.delete(recursive: true);
    }
    return 0;
  }

  Future<String> _arch(EnvConfig e) async {
    if (dryRun) return 'unknown';
    return (await ctx.query(
      e,
      "docker info --format '{{.Architecture}}'",
    )).trim();
  }
}

class AdoptCommand extends PodshipCommand {
  AdoptCommand() {
    argParser.addOption(
      'compose-dir',
      help:
          'The folder the running compose project was started from (default: the env dir).',
    );
  }
  @override
  String get name => 'adopt';
  @override
  String get description =>
      'Record a running setup that podship did not create as a release. Nothing restarts.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    final dir = argResults!['compose-dir'] as String? ?? e.dir;
    final (:state, :r) = await load(e);
    final scan = await scanForAdopt(ctx, e, dir, composeFilesOf(config, e));
    final work = await Directory.systemTemp.createTemp('podship-adopt-');
    try {
      await ctx.run(
        planAdopt(
          ctx: ctx,
          r: r,
          state: state,
          scan: scan,
          composeDir: dir,
          now: DateTime.now(),
          workDir: work.path,
        ),
      );
    } finally {
      await work.delete(recursive: true);
    }
    return 0;
  }
}

class StatusCommand extends PodshipCommand {
  StatusCommand() {
    argParser.addFlag(
      'watch',
      negatable: false,
      help: 'Refresh every few seconds.',
    );
    argParser.addOption(
      'interval',
      defaultsTo: '5',
      help: 'Seconds between refreshes with --watch.',
    );
  }
  @override
  String get name => 'status';
  @override
  String get description =>
      'The current release, previous releases, containers, health and disk.';

  @override
  Future<int> execute() async {
    final e = env;
    final watch = argResults!['watch'] == true;
    do {
      final (:state, :r) = await load(e);
      final l = EnvLayout(e);
      final out = await ctx.query(e, '''
if [ -x ${shq(l.currentComposeSh)} ]; then
  ${shq(l.currentComposeSh)} ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}\t{{.Ports}}' 2>&1 || true
else
  echo "(no current release)"
fi
echo "--"
if curl -fsS -o /dev/null --max-time 5 ${shq(r.healthUrl)}; then echo "health: ok (${r.healthUrl})"; else echo "health: FAILING (${r.healthUrl})"; fi
df -h ${shq(e.dir)} 2>/dev/null | tail -1 | awk '{print "disk: " \$4 " free of " \$2 " (" \$5 " used)"}'
du -sh ${shq(l.releases)} 2>/dev/null | awk '{print "releases on disk: " \$1}'
echo "--"
tail -n 5 ${shq(l.history)} 2>/dev/null || true
''');
      if (watch) stdout.write('\x1B[2J\x1B[H');
      stdout.writeln('${config.project} ${e.name} on ${e.host}:${e.dir}');
      stdout.writeln('current: ${state.current ?? '(none)'}');
      for (final rel in state.releases.reversed) {
        final m = rel.meta;
        stdout.writeln(
          '  ${rel.id == state.current ? '*' : ' '} ${rel.id}  ${rel.status.padRight(8)}'
          '${m == null ? '' : '  ${m.ref} ${m.sha.length > 7 ? m.sha.substring(0, 7) : m.sha}${m.promotedFrom == null ? '' : ' (promoted from ${m.promotedFrom})'}'}',
        );
      }
      stdout.writeln(
        'ports: ${r.ports.entries.map((x) => '${x.key}=${x.value}').join(' ')}',
      );
      stdout.write(out);
      if (watch) {
        await Future<void>.delayed(
          Duration(seconds: int.parse(argResults!['interval'] as String)),
        );
      }
    } while (watch);
    return 0;
  }
}

class ReleasesListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description => 'The releases kept on the server, newest first.';
  @override
  Future<int> execute() async {
    final e = env;
    final state = await fetchState(ctx, e);
    for (final rel in state.releases.reversed) {
      final m = rel.meta;
      stdout.writeln(
        [
          rel.id == state.current ? '*' : ' ',
          rel.id,
          rel.status,
          m?.createdAt ?? '',
          m?.createdBy ?? '',
          if (m?.promotedFrom != null) 'promoted from ${m!.promotedFrom}',
        ].join('  '),
      );
    }
    return 0;
  }
}

class HistoryCommand extends PodshipCommand {
  HistoryCommand() {
    argParser.addOption('limit', defaultsTo: '20');
  }
  @override
  String get name => 'history';
  @override
  String get description => 'Deploys, rollbacks and promotions, newest last.';
  @override
  Future<int> execute() async {
    final e = env;
    final l = EnvLayout(e);
    stdout.write(
      await ctx.query(
        e,
        'tail -n ${int.parse(argResults!['limit'] as String)} ${shq(l.history)} 2>/dev/null || true',
      ),
    );
    return 0;
  }
}

class LogsCommand extends PodshipCommand {
  LogsCommand() {
    argParser
      ..addMultiOption(
        'service',
        abbr: 's',
        help: 'Only these services (default: all).',
      )
      ..addOption('since', help: 'Like 10m, 2h or 2026-10-06T10:00.')
      ..addOption('until', help: 'Like 10m or 2026-10-06T12:00.')
      ..addOption('tail', defaultsTo: '100', help: 'Lines per service.')
      ..addFlag(
        'follow',
        abbr: 'f',
        negatable: false,
        help: 'Keep printing new lines.',
      )
      ..addFlag('timestamps', abbr: 't', negatable: false);
  }
  @override
  String get name => 'logs';
  @override
  String get description => 'Container logs of the current release.';
  @override
  Future<int> execute() async {
    final e = env;
    final l = EnvLayout(e);
    final a = argResults!;
    final services = [...a['service'] as List<String>, ...a.rest];
    final cmd = [
      shq(l.currentComposeSh),
      'logs',
      '--tail',
      shq(a['tail'] as String),
      if (a['since'] != null) ...['--since', shq(a['since'] as String)],
      if (a['until'] != null) ...['--until', shq(a['until'] as String)],
      if (a['follow'] == true) '--follow',
      if (a['timestamps'] == true) '--timestamps',
      ...services.map(shq),
    ].join(' ');
    return ctx.ssh.stream(
      e.host,
      ctx.header(e) + cmd,
      tty: a['follow'] == true && stdout.hasTerminal,
    );
  }
}
