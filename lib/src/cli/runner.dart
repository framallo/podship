// The podship command line.

import 'package:args/command_runner.dart';

import '../api/podship.dart' show podshipVersion;
import 'agent_commands.dart';
import 'backup_commands.dart';
import 'base.dart';
import 'console_commands.dart';
import 'console_install.dart';
import 'provider_commands.dart';
import 'db_commands.dart';
import 'image_commands.dart';
import 'integration_commands.dart';
import 'email_sender_command.dart';
import 'project_commands.dart';
import 'release_commands.dart';
import 'scheduler_commands.dart';
import 'watch_commands.dart';
import 'secret_commands.dart';
import 'self_commands.dart';
import 'server_commands.dart';

/// The version printed by `podship --version`.

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
        'json',
        negatable: false,
        help:
            'Machine-readable output: JSON documents for reads, JSON event lines for changes.',
      )
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
        'via',
        allowed: ['ssh', 'console'],
        help:
            'Run over ssh from here, or through the podship console (default: transport in podship.yaml).',
      )
      ..addOption(
        'ssh-key',
        help: 'An ssh private key for every connection (CI).',
      )
      ..addFlag(
        'notify',
        defaultsTo: null,
        help:
            'Send the notifications of notify: (default: as configured). --no-notify sends none.',
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
      GroupCommand(
        'tunnel',
        'Cloudflare Tunnels: list, route and unroute hostnames, create; forward a local port.',
        [
          TunnelListCommand(),
          TunnelRouteCommand(false),
          TunnelRouteCommand(true),
          TunnelCreateCommand(),
          TunnelForwardCommand(),
        ],
      ),
      GroupCommand(
        'dns',
        'DNS records in Cloudflare: plan, apply (after approval), list.',
        [DnsPlanCommand(), DnsApplyCommand(), DnsListCommand()],
      ),
      GroupCommand('email', 'The app\'s email sender in Amazon SES.', [
        EmailStatusCommand(),
        EmailSetupCommand(),
        EmailTestCommand(),
        EmailSenderCommand(),
      ]),
      GroupCommand(
        'app',
        'Set up or tear down an app: routes, DNS, TLS, email, as one plan.',
        [AppSetupCommand(), AppTeardownCommand()],
      ),
      HistoryCommand(),
      LoadtestCommand(),
      ScaleCommand(),
      UnlockCommand(),
      GroupCommand(
        'provider',
        'Providers: server providers (Vultr, Hostinger), Cloudflare and AWS: credentials, checks and offers.',
        [
          ProviderLoginCommand(),
          ProviderCheckCommand(),
          ProviderOffersCommand(),
        ],
      ),
      GroupCommand('console', 'The podship console: install it on a machine.', [
        ConsoleInstallCommand(),
      ]),
      LoginCommand(),
      LogoutCommand(),
      WhoamiCommand(),
      OperationsCommand(),
      GroupCommand(
        'self',
        'podship itself: build the compiled executable, show where it runs from.',
        [SelfUpdateCommand(), SelfPathCommand()],
      ),
      DestroyCommand(),
      GroupCommand('releases', 'Releases kept on the server.', [
        ReleasesListCommand(),
        ReleasesOverviewCommand(),
        ReleasesContainingCommand(),
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
      schedulerGroup(),
      watchGroup(),
      agentGroup(),
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
        'Domains, routed through a Cloudflare Tunnel or Caddy (TLS); DNS through Cloudflare.',
        [
          DomainListCommand(),
          DomainChangeCommand(false),
          DomainChangeCommand(true),
        ],
      ),
      GroupCommand(
        'server',
        'The server of an environment, shared by every project on it.',
        [
          BootstrapCommand(),
          ServerStatusCommand(),
          ServerCreateCommand(),
          ServerDestroyCommand(),
        ],
      ),
      GroupCommand(
        'images',
        'Images built on this machine and shipped to servers.',
        [ImagesCheckCommand(), ImagesPruneCommand()],
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
    final r = parse(compatArgs(args.toList()));
    if (r['version'] == true) {
      print('podship $podshipVersion'); // ignore: avoid_print
      return 0;
    }
    return runCommand(r);
  }
}

/// `podship tunnel --service …` (the port forward, before `tunnel` had
/// subcommands) still works: it means `podship tunnel forward …`.
List<String> compatArgs(List<String> args) {
  final i = args.indexOf('tunnel');
  if (i < 0) return args;
  const subs = {'list', 'route', 'unroute', 'create', 'forward', 'help'};
  final next = i + 1 < args.length ? args[i + 1] : null;
  if (next != null &&
      (subs.contains(next) || next == '--help' || next == '-h')) {
    return args;
  }
  if (next != null && !next.startsWith('-')) return args;
  if (next == null) return args;
  return [...args.sublist(0, i + 1), 'forward', ...args.sublist(i + 1)];
}
