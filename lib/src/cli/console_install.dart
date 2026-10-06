// console install: set up a podship console on a server, deployed by
// podship itself.
//
// It writes a small project (podship.yaml and a compose file) for the
// console image, then registers it, creates its secrets and its deploy key,
// deploys it, and routes its hostname through the server's tunnel. The
// console then runs operations with that deploy key (authorize it on other
// servers with `podship access add console --key <its public key>`).

import 'dart:io';

import 'package:path/path.dart' as p;

import '../ops/context.dart';
import 'base.dart';

String consoleConfig({
  required String host,
  required String dir,
  required String hostname,
  required String podshipHome,
  String? remotePath,
  String? tunnelConfig,
  String? tunnelService,
  String? tunnelId,
}) =>
    '''
# The podship console, deployed by podship. Written by `podship console install`.
project: podship-console
server_package: .
build:
  source: worktree
compose:
  files: [docker-compose.yml]
environments:
  production:
    host: $host
    dir: $dir
    podship_home: $podshipHome
${remotePath == null ? '' : '    remote_path: "$remotePath"\n'}    ports: {web: auto}
    health:
      url: "http://127.0.0.1:{port:web}/health"
    secrets:
      generate: [POSTGRES_PASSWORD, CONSOLE_SECRET]
      database_password_env: POSTGRES_PASSWORD
    database: {name: podship_console}
    backup:
      recipients: [~/.ssh/id_ed25519.pub]
${tunnelConfig == null ? '' : '''    proxy:
      kind: cloudflare_tunnel
      config: $tunnelConfig
      service: ${tunnelService ?? 'cloudflared'}
      tunnel_id: ${tunnelId ?? ''}
'''}    domains:
      - host: $hostname
        routes: [{port: web}]
''';

String consoleCompose(String image, String adminEmail, String dir) =>
    '''
# The podship console: a Serverpod app with its own Postgres. Its deploy key
# (shared/deploy_key) lets it run podship operations on registered servers.
services:
  server:
    image: $image
    restart: unless-stopped
    env_file: [.env]
    environment:
      runmode: production
      SERVERPOD_APPLY_MIGRATIONS: "true"
      SERVERPOD_DATABASE_HOST: postgres
      SERVERPOD_DATABASE_NAME: podship_console
      SERVERPOD_DATABASE_USER: postgres
      SERVERPOD_DATABASE_REQUIRE_SSL: "false"
      PODSHIP_CONSOLE_FIRST_ADMIN: "$adminEmail"
      PODSHIP_SSH_KEY: /run/podship/deploy_key
    volumes:
      - $dir/shared/deploy_key:/run/podship/deploy_key:ro
      - console-data:/data
    ports:
      - "127.0.0.1:\${PODSHIP_PORT_WEB:?}:8082"
    depends_on:
      postgres:
        condition: service_healthy
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_DB: podship_console
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD:?}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d podship_console"]
      interval: 10s
      retries: 10
volumes:
  pgdata:
  console-data:
''';

class ConsoleInstallCommand extends PodshipCommand {
  ConsoleInstallCommand() {
    argParser
      ..addOption(
        'host',
        mandatory: true,
        help: 'The ssh destination of the machine that runs the console.',
      )
      ..addOption(
        'hostname',
        mandatory: true,
        help: 'The public hostname, like console.example.com.',
      )
      ..addOption(
        'image',
        mandatory: true,
        help:
            'The console image, like ghcr.io/framallo/podship-console:latest.',
      )
      ..addOption(
        'admin',
        mandatory: true,
        help: 'The email of the first admin.',
      )
      ..addOption(
        'dir',
        defaultsTo: '/srv/podship-console',
        help: 'The folder on the machine.',
      )
      ..addOption('podship-home', defaultsTo: '/srv/podship')
      ..addOption(
        'remote-path',
        help: 'Added to PATH on the machine (macOS: /opt/homebrew/bin:…).',
      )
      ..addOption(
        'tunnel-config',
        help: 'The cloudflared config on the machine, to route the hostname.',
      )
      ..addOption(
        'tunnel-service',
        help: 'The systemd unit or launchd label of the tunnel.',
      )
      ..addOption('tunnel-id')
      ..addOption(
        'project',
        defaultsTo: 'podship-console',
        help: 'The local folder for the console project.',
      );
  }
  @override
  String get name => 'install';
  @override
  String get description =>
      'Set up a podship console on a machine with Docker: its project, secrets, deploy key, deploy and hostname.';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final a = argResults!;
    final dir = Directory(a['project'] as String)..createSync(recursive: true);
    File(p.join(dir.path, 'podship.yaml')).writeAsStringSync(
      consoleConfig(
        host: a['host'] as String,
        dir: a['dir'] as String,
        hostname: a['hostname'] as String,
        podshipHome: a['podship-home'] as String,
        remotePath: a['remote-path'] as String?,
        tunnelConfig: a['tunnel-config'] as String?,
        tunnelService: a['tunnel-service'] as String?,
        tunnelId: a['tunnel-id'] as String?,
      ),
    );
    File(p.join(dir.path, 'docker-compose.yml')).writeAsStringSync(
      consoleCompose(
        a['image'] as String,
        a['admin'] as String,
        a['dir'] as String,
      ),
    );
    log.ok('wrote ${dir.path}/podship.yaml and docker-compose.yml');
    final g = [
      '--project-dir',
      dir.path,
      if (yes) '--yes',
      if (verbose) '--verbose',
    ];
    final d = dryRun ? ['--dry-run'] : <String>[];
    final remoteDir = a['dir'] as String;
    final steps = <List<String>>[
      ['link', '--env', 'production', ...d],
      ['secret', 'init', '--env', 'production', ...d],
      [
        'deploy',
        '--env',
        'production',
        '--no-public-check',
        '--worktree',
        ...d,
      ],
      if (a['tunnel-config'] != null)
        ['domain', 'add', '--env', 'production', ...d],
      ['backup', 'schedule', '--env', 'production', ...d],
    ];
    if (!dryRun) {
      // The console's deploy key: created on the machine, never copied.
      final pub = await ssh.capture(a['host'] as String, '''
set -e
mkdir -p ${p.posix.join(remoteDir, 'shared')}
k=${p.posix.join(remoteDir, 'shared', 'deploy_key')}
[ -f "\$k" ] || ssh-keygen -q -t ed25519 -N '' -C podship-console -f "\$k"
cat "\$k.pub"
''');
      log.info(
        'The console deploy key (authorize it on servers with `podship access add console --key "<key>"`):',
      );
      log.info(pub.trim());
    }
    for (final s in steps) {
      log.info('\$ $exe ${s.join(' ')}');
      final code = await runner!.run([...g, ...s]) ?? 0;
      if (code != 0) {
        throw Aborted('console install stopped at: $exe ${s.join(' ')}');
      }
    }
    return 0;
  }
}
