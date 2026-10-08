// backup now|list|drill|restore|schedule|pull.

import 'dart:io';

import '../ops/context.dart';
import '../remote/ssh.dart';
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
      ..addFlag('remove', negatable: false, help: 'Remove the schedule.')
      ..addFlag(
        'show',
        negatable: false,
        help: 'Show the schedule and the last run.',
      );
  }
  @override
  String get name => 'schedule';
  @override
  String get description =>
      'Install the daily backup (systemd timer on Linux, launchd on macOS). Replaces a unit with the same name.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    if (argResults!['show'] == true) {
      final u = e.backup?.unit ?? (throw Aborted('no backup settings'));
      stdout.write(
        await ctx.query(e, '''
if [ "\$(uname -s)" = Darwin ]; then
  launchctl print gui/\$(id -u)/${shq(u)} 2>/dev/null | grep -E "state|last exit|path" || echo "not installed"
  tail -n 15 ${shq('${e.podshipHome}/log/$u.log')} 2>/dev/null || true
else
  systemctl list-timers ${shq('$u.timer')} --no-pager || true
  systemctl cat ${shq('$u.service')} 2>/dev/null | grep ExecStart || true
  journalctl -u ${shq(u)} -n 15 --no-pager -o cat || true
fi
'''),
      );
      return 0;
    }
    return runOp(
      api.backupSchedule(e.name, remove: argResults!['remove'] == true),
    );
  }
}

class BackupPullCommand extends PodshipCommand {
  BackupPullCommand() {
    argParser.addFlag(
      'install-agent',
      negatable: false,
      help:
          'Install a launchd agent on this Mac that pulls at 10:00, 16:00 and 22:00.',
    );
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
    if (argResults!['install-agent'] == true) return _installAgent(e.name);
    return runOp(api.backupPull(e.name));
  }

  Future<int> _installAgent(String envName) async {
    if (!Platform.isMacOS) throw Aborted('--install-agent is for macOS');
    final which = await Process.run('bash', ['-lc', 'command -v podship']);
    final bin = (which.stdout as String).trim();
    if (bin.isEmpty) throw Aborted('podship is not on PATH');
    final label = 'dev.podship.pull.${config.project}.$envName';
    final home = Platform.environment['HOME']!;
    final plist = '$home/Library/LaunchAgents/$label.plist';
    final logFile = '$home/Library/Logs/$label.log';
    final text =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by podship: pulls the encrypted ${config.project} $envName backups. -->
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>$bin</string><string>backup</string><string>pull</string><string>--env</string><string>$envName</string><string>--yes</string></array>
  <key>WorkingDirectory</key><string>${config.root}</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>${File(bin).parent.path}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Hour</key><integer>16</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Hour</key><integer>22</integer><key>Minute</key><integer>0</integer></dict>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$logFile</string>
  <key>StandardErrorPath</key><string>$logFile</string>
</dict>
</plist>
''';
    if (dryRun) {
      stdout.writeln('Would write $plist:\n$text');
      return 0;
    }
    final uid = (await Process.run('id', ['-u'])).stdout.toString().trim();
    final f = File(plist);
    final loaded =
        (await Process.run('launchctl', [
          'print',
          'gui/$uid/$label',
        ])).exitCode ==
        0;
    // macOS shows "can run in the background" every time an agent is
    // registered again: register only when the plist changed or it is not
    // loaded.
    if (loaded && f.existsSync() && f.readAsStringSync() == text) {
      log.ok('$label unchanged and loaded; log: $logFile');
      return 0;
    }
    f.writeAsStringSync(text);
    await Process.run('launchctl', ['bootout', 'gui/$uid/$label']);
    final r = await Process.run('launchctl', ['bootstrap', 'gui/$uid', plist]);
    if (r.exitCode != 0) throw Aborted('launchctl: ${r.stderr}');
    log.ok('installed $label; log: $logFile');
    return 0;
  }
}
