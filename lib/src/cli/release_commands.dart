// deploy, rollback, promote, adopt, restart, status, logs, releases, history.

import 'dart:convert' show jsonEncode;
import 'dart:io';

import '../api/models.dart';
import '../config/config.dart';
import '../ops/context.dart';
import '../ops/deploy.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../protocol/protocol.dart';
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
        'skip-tests',
        negatable: false,
        help: 'Skip the test stage (needs --reason; recorded in history).',
      )
      ..addOption('reason', help: 'Why the tests are skipped.')
      ..addOption(
        'confirm',
        help:
            'The environment name, to confirm an untested deploy without a terminal.',
      )
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
    final skipTests = a['skip-tests'] == true;
    final reason = a['reason'] as String?;
    if (skipTests && (reason == null || reason.trim().isEmpty)) {
      usageException('--skip-tests needs --reason "<why>"');
    }
    var confirmedUntested = false;
    if (skipTests && config.tests.gate.contains(e.name)) {
      confirmEnvName(
        e.name,
        'Deploy to ${e.name} WITHOUT running tests ($reason).',
        a['confirm'] as String?,
      );
      confirmedUntested = true;
    }
    return runOp(
      api.deploy(
        e.name,
        ref: a['ref'] as String?,
        skipTestsReason: skipTests ? reason : null,
        confirmedUntested: confirmedUntested,
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
    argParser
      ..addOption(
        'release',
        help: 'The release to promote (default: the one running on <from>).',
      )
      ..addFlag(
        'skip-tests',
        negatable: false,
        help:
            'Promote a release whose commit has no passing tests (needs --reason).',
      )
      ..addOption('reason', help: 'Why the tests are skipped.')
      ..addOption(
        'confirm',
        help: 'The target environment name, to confirm without a terminal.',
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
    final skipTests = argResults!['skip-tests'] == true;
    final reason = argResults!['reason'] as String?;
    if (skipTests && (reason == null || reason.trim().isEmpty)) {
      usageException('--skip-tests needs --reason "<why>"');
    }
    if (skipTests && config.tests.gate.contains(to.name)) {
      confirmEnvName(
        to.name,
        'Promote to ${to.name} without passing tests ($reason).',
        argResults!['confirm'] as String?,
      );
    }
    return runOp(
      api.promote(
        rest[0],
        rest[1],
        release: argResults!['release'] as String?,
        skipTestsReason: skipTests ? reason : null,
        confirmedUntested: skipTests,
      ),
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
  @override
  OperationRequest? get consoleRead => request('status');
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
    for (final t in s.logTables.entries) {
      stdout.writeln(
        '${t.key}: ${t.value['rows']} rows, ${(t.value['bytes']! / 1048576).toStringAsFixed(1)} MB',
      );
    }
  }
}

class ReleasesListCommand extends PodshipCommand {
  @override
  OperationRequest? get consoleRead => request('releases.list');
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
  @override
  OperationRequest? get consoleRead => request('history', {
    'limit': int.parse(argResults!['limit'] as String),
    'all_projects': argResults!['all'] == true,
  });
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

class UnlockCommand extends PodshipCommand {
  @override
  String get name => 'unlock';
  @override
  String get description =>
      'Remove the environment lock left by a client that stopped in the middle of an operation.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    final held = await api.lockHolder(e.name);
    if (held != null &&
        !ctx.confirm(
          'Remove the lock of ${held['actor']} (${held['operation']}, since ${held['started_at']})?',
        )) {
      throw Aborted('cancelled');
    }
    return runOp(api.unlock(e.name));
  }
}

class ReleasesOverviewCommand extends PodshipCommand {
  @override
  String get name => 'overview';
  @override
  String get description =>
      'What runs where: every environment, its current release and commit.';
  @override
  bool get takesEnv => false;
  @override
  OperationRequest? get consoleRead =>
      OperationRequest(operation: 'releases.overview', project: config.project);
  @override
  Future<int> execute() async {
    final list = await api.overview();
    if (json) {
      printJson(list);
      return 0;
    }
    for (final o in list) {
      final sha = o['current_sha'] as String?;
      stdout.writeln(
        '${'${o['env']}'.padRight(12)} ${'${o['host']}'.padRight(24)} '
        '${o['error'] != null ? 'ERROR ${o['error']}' : '${o['current'] ?? '(none)'}  ${sha == null ? '' : sha.substring(0, 7)}'}',
      );
    }
    return 0;
  }
}

class ReleasesContainingCommand extends PodshipCommand {
  @override
  String get name => 'containing';
  @override
  String get description =>
      'Which environments run a release that contains a commit.';
  @override
  String get invocation => '$exe releases containing <sha>';
  @override
  bool get takesEnv => false;
  @override
  OperationRequest? get consoleRead => argResults!.rest.length == 1
      ? OperationRequest(
          operation: 'releases.containing',
          project: config.project,
          params: {'sha': argResults!.rest.single},
        )
      : null;
  @override
  Future<int> execute() async {
    if (argResults!.rest.length != 1) usageException('give one commit');
    final list = await api.releasesContaining(argResults!.rest.single);
    if (json) {
      printJson(list);
      return 0;
    }
    for (final o in list) {
      stdout.writeln(
        '${'${o['env']}'.padRight(12)} ${switch (o['contains']) {
          true => 'yes',
          false => 'no ',
          _ => '?  ',
        }}  ${o['current'] ?? '(none)'}',
      );
    }
    return 0;
  }
}

class LoadtestCommand extends PodshipCommand {
  LoadtestCommand() {
    argParser
      ..addOption('path', defaultsTo: '/health')
      ..addOption('users', defaultsTo: '10', help: 'Virtual users.')
      ..addOption('duration', defaultsTo: '30s')
      ..addOption('port', defaultsTo: 'web', help: 'A port name from ports:.');
  }
  @override
  String get name => 'loadtest';
  @override
  String get description =>
      'Load test an environment with k6, from its own server. Prints latency and errors.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    if (e.isProduction &&
        !ctx.confirm('Load test PRODUCTION (real users share it)?')) {
      throw Aborted('cancelled');
    }
    final a = argResults!;
    return runOp(
      api.loadtest(
        e.name,
        path: a['path'] as String,
        vus: int.parse(a['users'] as String),
        duration: a['duration'] as String,
        port: a['port'] as String,
      ),
    );
  }
}

class ScaleCommand extends PodshipCommand {
  ScaleCommand() {
    argParser.addOption(
      'replicas',
      mandatory: true,
      help:
          'Server containers in total (at least 2 for a release made with serverpod.replicas > 1).',
    );
  }
  @override
  String get name => 'scale';
  @override
  String get description =>
      'Change the number of server containers of the current release. The release must have been deployed with serverpod.replicas > 1 (load balancer and Redis); to go from 1 to more, set serverpod.replicas and deploy.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    final n = int.parse(argResults!['replicas'] as String);
    if (n < 2) {
      usageException(
        '--replicas must be 2 or more; for 1, set serverpod.replicas: 1 and deploy',
      );
    }
    return runOp(api.scale(e.name, n));
  }
}
