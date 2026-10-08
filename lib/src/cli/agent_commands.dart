// `podship agent …`: the backup and restore steps that run on the server
// itself, from the binary at `<podship home>/bin/podship`. podship sends
// one short command over ssh; the scheduler runs `agent backup` at night.
// These commands read only the settings file, never `podship.yaml`.

import 'dart:io';

import 'package:args/command_runner.dart';

import '../agent/backup_agent.dart';
import '../agent/restore_agent.dart';
import '../agent/settings.dart';
import 'base.dart';

abstract class _AgentCommand extends Command<int> {
  _AgentCommand() {
    argParser.addOption(
      'conf',
      mandatory: true,
      help: 'The settings file podship wrote (<home>/etc/<unit>.conf).',
    );
  }

  /// The prefix of error lines.
  String get tag;

  BackupSettings get settings =>
      BackupSettings.load(argResults!['conf'] as String);

  Future<int> execute();

  @override
  Future<int> run() async {
    try {
      return await execute();
    } on AgentFailure catch (e) {
      stderr.writeln('[$tag] ERROR: ${e.message}');
      return 1;
    }
  }
}

class AgentBackupCommand extends _AgentCommand {
  AgentBackupCommand() {
    argParser.addFlag(
      'list',
      negatable: false,
      help: 'Print "STAMP SIZE ENCRYPTED" lines and take no backup.',
    );
  }
  @override
  String get name => 'backup';
  @override
  String get description =>
      'On the server: take a backup (pg_dump, volumes, age copy), then prune.';
  @override
  String get tag => 'backup';
  @override
  Future<int> execute() async {
    final a = BackupAgent(settings);
    if (argResults!['list'] == true) {
      a.list().forEach(stdout.writeln);
      return 0;
    }
    await a.backup();
    return 0;
  }
}

class AgentDrillCommand extends _AgentCommand {
  @override
  String get name => 'drill';
  @override
  String get description =>
      'On the server: restore a backup into a throwaway postgres and compare row counts. [STAMP]';
  @override
  String get tag => 'restore';
  @override
  Future<int> execute() async {
    final rest = argResults!.rest;
    await RestoreAgent(
      settings,
    ).drill(RestoreSource(stamp: rest.isEmpty ? null : rest.first));
    return 0;
  }
}

class AgentRestoreCommand extends _AgentCommand {
  AgentRestoreCommand() {
    argParser
      ..addOption(
        'confirmed',
        mandatory: true,
        help: 'The project name the user typed.',
      )
      ..addOption('dump', help: 'Restore this dump file.')
      ..addOption('dir', help: 'Restore this backup folder (from elsewhere).')
      ..addFlag(
        'volumes',
        negatable: false,
        help: 'Also replace the volumes with the archives of the backup.',
      );
  }
  @override
  String get name => 'restore';
  @override
  String get description =>
      'On the server: back up, stop, rename the database, restore, start. [STAMP]';
  @override
  String get tag => 'restore';
  @override
  Future<int> execute() async {
    final a = argResults!;
    await RestoreAgent(settings).restore(
      RestoreSource(
        stamp: a.rest.isEmpty ? null : a.rest.first,
        dump: a['dump'] as String?,
        dir: a['dir'] as String?,
      ),
      confirmed: a['confirmed'] as String,
      volumes: a['volumes'] == true,
    );
    return 0;
  }
}

/// The agent commands as a group.
Command<int> agentGroup() => GroupCommand(
  'agent',
  'Steps that run on the server itself (backup, drill, restore). podship and the scheduler call them.',
  [AgentBackupCommand(), AgentDrillCommand(), AgentRestoreCommand()],
);
