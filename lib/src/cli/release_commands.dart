// deploy, rollback, promote, adopt, restart, status, logs, releases, history.

import 'dart:convert' show jsonEncode;
import 'dart:io';

import '../api/models.dart';
import '../config/config.dart';
import '../ops/context.dart';
import '../ops/deploy.dart';
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
    final a = argResults!;
    if (e.isProduction &&
        !ctx.confirm(
          'Deploy ${a['ref'] ?? config.build.ref} to PRODUCTION on ${e.host}?',
        )) {
      throw Aborted('cancelled');
    }
    return runOp(
      api.deploy(
        e.name,
        ref: a['ref'] as String?,
        options: DeployOptions(
          source: a['worktree'] == true ? SourceMode.worktree : null,
          skipWeb: a['skip-web'] == true,
          skipBackup: a['skip-backup'] == true,
          skipHooks: a['skip-hooks'] == true,
          publicCheck: a['public-check'] == true,
        ),
      ),
    );
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
    final withDb = argResults!['with-db'] as String?;
    if (withDb != null) {
      ctx.typeProjectName(
        'This replaces the ${e.name} database with backup $withDb (the current one is renamed, not dropped).',
        typed: argResults!['confirm'] as String?,
      );
    } else if (e.isProduction &&
        !ctx.confirm('Roll back PRODUCTION (code only)?')) {
      throw Aborted('cancelled');
    }
    return runOp(
      api.rollback(e.name, to: argResults!['to'] as String?, withDb: withDb),
    );
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
  Future<int> execute() async =>
      runOp(api.restart(guardedEnv.name, services: argResults!.rest));
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
    final to = config.env(rest[1]);
    if (to.isProduction &&
        !ctx.confirm('Promote ${rest[0]} to PRODUCTION on ${to.host}?')) {
      throw Aborted('cancelled');
    }
    return runOp(
      api.promote(rest[0], rest[1], release: argResults!['release'] as String?),
    );
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
  Future<int> execute() async => runOp(
    api.adopt(env.name, composeDir: argResults!['compose-dir'] as String?),
  );
}

class StatusCommand extends PodshipCommand {
  StatusCommand() {
    argParser
      ..addFlag('watch', negatable: false, help: 'Refresh every few seconds.')
      ..addOption(
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
      final s = await api.status(e.name);
      if (json) {
        printJson(s.toJson());
      } else {
        if (watch) stdout.write('\x1B[2J\x1B[H');
        _print(s);
      }
      if (watch) {
        await Future<void>.delayed(
          Duration(seconds: int.parse(argResults!['interval'] as String)),
        );
      }
    } while (watch);
    return 0;
  }

  void _print(EnvStatus s) {
    String gb(int? kb) =>
        kb == null ? '?' : '${(kb / 1024 / 1024).toStringAsFixed(1)} GB';
    stdout.writeln('${config.project} ${s.env} on ${s.host}:${s.dir}');
    stdout.writeln('current: ${s.current ?? '(none)'}');
    for (final r in s.releases) {
      final m = r.meta;
      stdout.writeln(
        '  ${r.id == s.current ? '*' : ' '} ${r.id}  ${r.status.padRight(8)}'
        '${m == null ? '' : '  ${m.ref} ${m.sha.length > 7 ? m.sha.substring(0, 7) : m.sha}${m.promotedFrom == null ? '' : ' (promoted from ${m.promotedFrom})'}'}',
      );
    }
    stdout.writeln(
      'ports: ${s.ports.entries.map((x) => '${x.key}=${x.value}').join(' ')}',
    );
    stdout.writeln('health: ${s.healthy ? 'ok' : 'FAILING'} (${s.healthUrl})');
    for (final c in s.containers) {
      stdout.writeln(
        '  ${c.service.padRight(12)} ${c.state.padRight(9)} ${c.status.padRight(24)} ${c.ports}',
      );
    }
    stdout.writeln(
      'disk: ${gb(s.diskFreeKb)} free of ${gb(s.diskTotalKb)}; releases use ${gb(s.releasesKb)}',
    );
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
    final current = await api.currentRelease(e.name);
    final list = await api.releases(e.name);
    if (json) {
      printJson([for (final r in list) r.toJson(current: current)]);
      return 0;
    }
    for (final r in list) {
      final m = r.meta;
      stdout.writeln(
        [
          r.id == current ? '*' : ' ',
          r.id,
          r.status,
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
    argParser
      ..addOption('limit', defaultsTo: '20')
      ..addFlag(
        'all',
        negatable: false,
        help: 'Every project and environment on the server.',
      );
  }
  @override
  String get name => 'history';
  @override
  String get description =>
      'Deploys, rollbacks, backups and restores, with who, when and the outcome.';
  @override
  Future<int> execute() async {
    final list = await api.history(
      env.name,
      limit: int.parse(argResults!['limit'] as String),
      allProjects: argResults!['all'] == true,
    );
    if (json) {
      printJson([for (final r in list) r.toJson()]);
      return 0;
    }
    for (final r in list) {
      final j = r.json;
      stdout.writeln(
        [
          r.startedAt.split('.').first,
          '${r.project}/${r.env}',
          r.operation.padRight(15),
          r.ok ? 'ok    ' : 'FAILED',
          '${((j['duration_ms'] as num? ?? 0) / 1000).toStringAsFixed(1)} s'
              .padLeft(8),
          if (r.release != null) r.release!,
          '${j['actor'] ?? ''}',
          if (!r.ok) '${j['error'] ?? ''}',
        ].join('  '),
      );
    }
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
    final a = argResults!;
    final services = [...a['service'] as List<String>, ...a.rest];
    if (a['follow'] == true && stdout.hasTerminal && !json) {
      // A terminal gets the real stream, with Ctrl+C handled by ssh.
      final l = EnvLayout(e);
      final cmd = [
        shq(l.currentComposeSh),
        'logs',
        '--tail',
        shq(a['tail'] as String),
        if (a['since'] != null) ...['--since', shq(a['since'] as String)],
        if (a['until'] != null) ...['--until', shq(a['until'] as String)],
        '--follow',
        if (a['timestamps'] == true) '--timestamps',
        ...services.map(shq),
      ].join(' ');
      return ctx.ssh.stream(e.host, ctx.header(e) + cmd, tty: true);
    }
    await for (final line in api.logs(
      e.name,
      services: services,
      since: a['since'] as String?,
      until: a['until'] as String?,
      tail: int.parse(a['tail'] as String),
      follow: a['follow'] == true,
      timestamps: a['timestamps'] == true,
    )) {
      stdout.writeln(json ? jsonEncode({'line': line}) : line);
    }
    return 0;
  }
}
