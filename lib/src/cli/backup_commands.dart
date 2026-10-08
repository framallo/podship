// backup now|list|drill|restore|schedule|pull.

import 'dart:io';

import '../protocol/protocol.dart';
import 'base.dart';

class BackupNowCommand extends PodshipCommand {
  @override
  String get name => 'now';
  @override
  String get description =>
      'Take a backup now (database, volumes, encrypted copy).';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async => runOp(api.backupNow(env.name));
}

class BackupListCommand extends PodshipCommand {
  @override
  OperationRequest? get consoleRead => request('backup.list');
  @override
  String get name => 'list';
  @override
  String get description =>
      'Backups on the server: stamp, size, encrypted copy.';
  @override
  Future<int> execute() async {
    final list = await api.backups(env.name);
    if (json) {
      printJson([for (final b in list) b.toJson()]);
    } else {
      for (final b in list) {
        stdout.writeln(
          '${b.stamp}  ${b.size.padLeft(6)}  ${b.encrypted ? 'encrypted copy' : 'no encrypted copy'}',
        );
      }
    }
    return 0;
  }
}

class BackupDrillCommand extends PodshipCommand {
  @override
  String get name => 'drill';
  @override
  String get description =>
      'Restore a backup into a throwaway container and compare row counts. Touches nothing live.';
  @override
  String get invocation => '$exe backup drill [STAMP] [--env <env>]';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async => runOp(
    api.backupDrill(
      env.name,
      stamp: argResults!.rest.isEmpty ? null : argResults!.rest.first,
    ),
  );
}

class BackupRestoreCommand extends PodshipCommand {
  BackupRestoreCommand() {
    argParser
      ..addOption(
        'dump',
        help: 'Restore this local pg_dump -Fc file instead of a server backup.',
      )
      ..addOption(
        'from',
        help:
            'Restore a backup of this other environment (it may be on another server).',
      )
      ..addFlag(
        'volumes',
        negatable: false,
        help:
            'Also replace the configured Docker volumes with the backup archives.',
      )
      ..addOption(
        'confirm',
        help: 'The project name, to confirm without a terminal.',
      );
  }
  @override
  String get name => 'restore';
  @override
  String get description =>
      'Replace the database with a backup. Takes a backup first, renames the current database (no drop).';
  @override
  String get invocation =>
      '$exe backup restore [STAMP | --dump FILE] [--env <env>]';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    final stamp = argResults!.rest.isEmpty ? null : argResults!.rest.first;
    ctx.typeProjectName(
      'This replaces the ${e.name} database of ${config.project} on ${e.host} '
      'with ${stamp ?? argResults!['dump'] ?? 'the newest backup'}. The current database is renamed, not dropped.',
      typed: argResults!['confirm'] as String?,
    );
    return runOp(
      api.backupRestore(
        e.name,
        stamp: stamp,
        dumpFile: argResults!['dump'] as String?,
        fromEnv: argResults!['from'] as String?,
        volumes: argResults!['volumes'] == true,
      ),
    );
  }
}

class BackupScheduleCommand extends PodshipCommand {
  BackupScheduleCommand() {
    argParser
      ..addFlag('remove', negatable: false, help: 'Remove the backup job.')
      ..addFlag(
        'show',
        negatable: false,
        help: 'Show the job, its last run and the scheduler of the server.',
      );
  }
  @override
  String get name => 'schedule';
  @override
  String get description =>
      'Write the nightly backup job into the server registry. The server\'s podship scheduler runs it (no launchd or systemd unit per environment).';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    if (argResults!['show'] == true) {
      final st = await api.schedulerStatusOf(envName: e.name);
      final mine = [
        for (final j in st.jobs)
          if (j['project'] == config.project && j['env'] == e.name) j,
      ];
      if (json) {
        printJson({...st.toJson(), 'jobs': mine});
        return 0;
      }
      stdout.writeln(
        'scheduler on ${e.host}: ${st.agentLoaded ? 'installed' : 'NOT installed'}, '
        'nightly at ${st.registry.scheduler.at}'
        '${st.state['last_tick'] == null ? '' : ', last run ${st.state['last_tick']}'}',
      );
      if (mine.isEmpty) {
        stdout.writeln(
          'no job for ${config.project}/${e.name}: run `podship backup schedule --env ${e.name}`',
        );
      }
      for (final j in mine) {
        stdout.writeln(formatJob(j));
      }
      return 0;
    }
    return runOp(
      api.backupSchedule(e.name, remove: argResults!['remove'] == true),
    );
  }
}

/// One line per job: id, enabled, last run and its outcome.
String formatJob(Map<String, Object?> j) {
  final last = j['last_run'];
  final ok = j['last_ok'];
  return '${'${j['id']}'.padRight(40)} '
      '${j['enabled'] == false ? 'off     ' : 'nightly '} '
      '${last == null ? 'never ran' : 'last $last ${ok == true ? 'ok' : 'FAILED${j['last_error'] == null ? '' : ' (${j['last_error']})'}'}'
                '${j['last_stamp'] == null ? '' : ' stamp ${j['last_stamp']}'}'}';
}

class BackupPullCommand extends PodshipCommand {
  BackupPullCommand() {
    argParser
      ..addFlag(
        'schedule',
        negatable: false,
        help:
            'Do not pull now: write the nightly pull job into this machine\'s registry (its podship scheduler runs it).',
      )
      ..addFlag(
        'remove',
        negatable: false,
        help: 'With --schedule: remove the pull job.',
      )
      ..addFlag('install-agent', negatable: false, hide: true);
  }
  @override
  String get name => 'pull';
  @override
  String get description =>
      'Copy the encrypted backups to this machine (off-site) and check the newest one.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    if (argResults!['install-agent'] == true) {
      log.info(
        '--install-agent is now --schedule: the pull is a job of this machine\'s scheduler',
      );
    }
    if (argResults!['schedule'] == true ||
        argResults!['install-agent'] == true) {
      return runOp(
        api.backupPullSchedule(e.name, remove: argResults!['remove'] == true),
      );
    }
    return runOp(api.backupPull(e.name));
  }
}
