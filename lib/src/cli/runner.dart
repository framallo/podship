// The podship command line.

import 'package:args/command_runner.dart';

import 'backup_commands.dart';
import 'base.dart';
import 'db_commands.dart';
import 'project_commands.dart';
import 'release_commands.dart';
import 'secret_commands.dart';
import 'server_commands.dart';

/// The version printed by `podship --version`.
const podshipVersion = '0.1.0';

class PodshipRunner extends CommandRunner<int> {
  PodshipRunner()
    : super(
        exe,
        'Deploy, back up and roll back Serverpod projects on your own servers, '
        'with production and staging.\n\n'
        'Commands that change something accept --dry-run. Commands that can '
        'destroy data default to --env staging; production must be named.',
      ) {
    argParser
      ..addFlag('version', negatable: false, help: 'Print the version.')
      ..addFlag('verbose', abbr: 'v', negatable: false)
      ..addFlag('quiet', abbr: 'q', negatable: false)
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Answer yes to confirmations (CI).',
      )
      ..addOption(
        'project-dir',
        abbr: 'C',
        help: 'The folder of podship.yaml (default: here or above).',
      )
      ..addOption(
        'ssh-key',
        help: 'An ssh private key for every connection (CI).',
      );
    for (final c in <Command<int>>[
      InitCommand(),
      LaunchCommand(),
      DoctorCommand(),
      LinkCommand(),
      DeployCommand(),
      RollbackCommand(),
      PromoteCommand(),
      RestartCommand(),
      AdoptCommand(),
      StatusCommand(),
      LogsCommand(),
      TunnelCommand(),
      DestroyCommand(),
      GroupCommand('releases', 'Releases kept on the server.', [
        ReleasesListCommand(),
        HistoryCommand(),
      ]),
      GroupCommand(
        'env',
        'Plain variables in the environment\'s .env (on the server).',
        [EnvListCommand(), EnvGetCommand(), EnvSetCommand(), EnvUnsetCommand()],
      ),
      GroupCommand(
        'secret',
        'Secrets in .env and passwords.yaml (on the server; values never shown).',
        [
          SecretInitCommand(),
          SecretListCommand(),
          SecretSetCommand(),
          SecretUnsetCommand(),
          SecretCopyCommand(),
        ],
      ),
      GroupCommand(
        'backup',
        'Database and volume backups, encrypted off-site copies, restore.',
        [
          BackupNowCommand(),
          BackupListCommand(),
          BackupDrillCommand(),
          BackupRestoreCommand(),
          BackupScheduleCommand(),
          BackupPullCommand(),
        ],
      ),
      GroupCommand('db', 'The environment database.', [
        DbConnectCommand(),
        DbProvisionCommand(),
        DbWipeCommand(),
        GroupCommand('migrate', 'Serverpod migrations.', [
          DbMigrateStatusCommand(),
        ]),
        GroupCommand('user', 'Database roles for people and tools.', [
          DbUserCommand('list'),
          DbUserCommand('create'),
          DbUserCommand('reset-password'),
          DbUserCommand('delete'),
        ]),
      ]),
      GroupCommand(
        'domain',
        'Domains, routed through a Cloudflare Tunnel or Caddy (TLS).',
        [DomainListCommand(), DomainAddCommand(false), DomainAddCommand(true)],
      ),
      GroupCommand(
        'server',
        'The server of an environment, shared by every project on it.',
        [BootstrapCommand(), ServerStatusCommand()],
      ),
      GroupCommand('projects', 'Projects registered on a server.', [
        ProjectsListCommand(),
      ]),
      GroupCommand('access', 'Per-person ssh keys on a server.', [
        AccessCommand('list'),
        AccessCommand('add'),
        AccessCommand('remove'),
      ]),
      GroupCommand('ci', 'Deploy from CI with an ssh deploy key.', [
        CiSetupCommand(),
      ]),
    ]) {
      addCommand(c);
    }
  }

  @override
  Future<int?> run(Iterable<String> args) async {
    final r = parse(args);
    if (r['version'] == true) {
      print('podship $podshipVersion'); // ignore: avoid_print
      return 0;
    }
    return runCommand(r);
  }
}
