// server, projects, link, destroy, domain, access, ci.

import 'dart:io';

import '../ops/backup_ops.dart';
import '../ops/context.dart';
import '../ops/server_ops.dart';
import '../protocol/protocol.dart';
import 'base.dart';

class BootstrapCommand extends PodshipCommand {
  BootstrapCommand() {
    argParser
      ..addFlag(
        'caddy',
        negatable: false,
        help: 'Also install Caddy (automatic TLS).',
      )
      ..addFlag(
        'firewall',
        defaultsTo: true,
        help:
            'Allow ssh (and 80/443 with --caddy) in ufw; enable ufw if it is off.',
      )
      ..addOption(
        'user',
        help: 'Also create this user and add it to the docker group.',
      );
  }
  @override
  String get name => 'bootstrap';
  @override
  String get description =>
      'Prepare a server: Docker, compose, age, zstd, firewall, folders. Safe to run again.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async => runOp(
    api.bootstrap(
      env.name,
      caddy: argResults!['caddy'] == true,
      firewall: argResults!['firewall'] == true,
      user: argResults!['user'] as String?,
    ),
  );
}

class ServerStatusCommand extends PodshipCommand {
  @override
  OperationRequest? get consoleRead => request('server.status');
  @override
  String get name => 'status';
  @override
  String get description =>
      'Every project on the server of --env: registry, containers, CPU, memory, disk.';
  @override
  Future<int> execute() async {
    final s = await api.serverStatus(env.name);
    if (json) {
      printJson(s.toJson());
      return 0;
    }
    stdout.writeln('Server ${s.host}:');
    registryTable(s.registry).forEach((x) => stdout.writeln('  $x'));
    stdout.writeln('\nContainers:');
    for (final c in s.containers) {
      stdout.writeln(
        '  ${'${c['name']}'.padRight(34)} ${'${c['project'] ?? '-'}'.padRight(24)} '
        '${'${c['cpu'] ?? ''}'.padLeft(7)}  ${'${c['memory'] ?? ''}'.padRight(22)} ${c['status']}',
      );
    }
    if (s.diskFreeKb != null) {
      stdout.writeln(
        '\nDisk /: ${(s.diskFreeKb! / 1048576).toStringAsFixed(1)} GB free of ${(s.diskTotalKb! / 1048576).toStringAsFixed(1)} GB',
      );
    }
    return 0;
  }
}

class ProjectsListCommand extends PodshipCommand {
  @override
  OperationRequest? get consoleRead => request('projects.list');
  @override
  String get name => 'list';
  @override
  String get description =>
      'The projects and environments registered on the server of --env.';
  @override
  Future<int> execute() async {
    final reg = await api.projects(env.name);
    json
        ? printJson([for (final e in reg.entries.values) e.toMap()])
        : registryTable(reg).forEach(stdout.writeln);
    return 0;
  }
}

class LinkCommand extends PodshipCommand {
  @override
  String get name => 'link';
  @override
  String get description =>
      'Register this environment in the server registry: ports, domains, database, backup slot.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async => runOp(api.link(env.name));
}

class DestroyCommand extends PodshipCommand {
  DestroyCommand() {
    argParser
      ..addFlag(
        'purge-backups',
        negatable: false,
        help: 'Also delete the backups on the server.',
      )
      ..addOption(
        'confirm',
        help: 'The project name, to confirm without a terminal.',
      );
  }
  @override
  String get name => 'destroy';
  @override
  String get description =>
      'Remove an environment: containers, volumes, images, files, routes, schedule, registry entry.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    ctx.typeProjectName(
      'This DELETES ${config.project}/${e.name} on ${e.host}, its database volume included.',
      typed: argResults!['confirm'] as String?,
    );
    return runOp(
      api.destroy(e.name, purgeBackups: argResults!['purge-backups'] == true),
    );
  }
}

class DomainListCommand extends PodshipCommand {
  @override
  OperationRequest? get consoleRead => request('domain.list');
  @override
  String get name => 'list';
  @override
  String get description =>
      'Domains in podship.yaml, the routes on the proxy, and DNS answers.';
  @override
  Future<int> execute() async {
    final list = await api.domains(env.name);
    if (json) {
      printJson([for (final d in list) d.toJson()]);
      return 0;
    }
    for (final d in list) {
      stdout.writeln(
        '${d.host}: ${d.routes.join(', ')}  DNS: ${d.dnsAnswers.isEmpty ? 'no answer' : d.dnsAnswers.join(' ')}',
      );
      stdout.writeln('  needs: ${d.dnsNeeded}');
      for (final r in d.proxyRules) {
        stdout.writeln('  proxy: $r');
      }
    }
    return 0;
  }
}

class AccessCommand extends PodshipCommand {
  AccessCommand(this._action) {
    if (_action == 'add') {
      argParser.addOption(
        'key',
        mandatory: true,
        help:
            'A public key file (like ~/.ssh/id_ed25519.pub) or the key itself.',
      );
    }
  }
  final String _action;
  @override
  String get name => _action;
  @override
  String get description => switch (_action) {
    'add' =>
      'Give a person (or CI) ssh access to the server of --env with their own key.',
    'remove' => "Remove a person's key from the server of --env.",
    _ => 'People with a podship-managed key on the server of --env.',
  };
  @override
  String get invocation =>
      '$exe access $_action${_action == 'list' ? '' : ' NAME'} [--env <env>]';
  @override
  bool get mutating => _action != 'list';
  @override
  Future<int> execute() async {
    final e = env;
    if (_action == 'list') {
      final out = await ctx.query(
        e,
        r'''grep -o 'podship:[A-Za-z0-9._@-]*' ~/.ssh/authorized_keys 2>/dev/null | sed 's/^podship://' || true''',
      );
      final names = out.trim().isEmpty ? <String>[] : out.trim().split('\n');
      json ? printJson(names) : names.forEach(stdout.writeln);
      return 0;
    }
    if (argResults!.rest.length != 1) usageException('give one NAME');
    String? key;
    if (_action == 'add') {
      final k = argResults!['key'] as String;
      final f = File(expandHome(k));
      key = f.existsSync() ? f.readAsStringSync() : k;
    }
    return runOp(
      api.access(e.name, _action, argResults!.rest.single, publicKey: key),
    );
  }
}

class CiSetupCommand extends PodshipCommand {
  CiSetupCommand() {
    argParser
      ..addOption('name', defaultsTo: 'ci', help: 'The key name on the server.')
      ..addOption(
        'out',
        defaultsTo: '.podship-ci',
        help: 'Where to write the key pair (keep it out of git).',
      );
  }
  @override
  String get name => 'setup';
  @override
  String get description =>
      'Create an ssh deploy key for CI, give it access, and print the workflow to use it.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    final who = argResults!['name'] as String;
    final out = argResults!['out'] as String;
    final key = '$out/id_ed25519';
    if (!dryRun) {
      Directory(out).createSync(recursive: true);
      if (!File(key).existsSync()) {
        final r = await Process.run('ssh-keygen', [
          '-q',
          '-t',
          'ed25519',
          '-N',
          '',
          '-C',
          'podship-$who',
          '-f',
          key,
        ]);
        if (r.exitCode != 0) throw Aborted('ssh-keygen: ${r.stderr}');
      }
    }
    final pub = dryRun
        ? 'ssh-ed25519 AAAA podship-$who'
        : File('$key.pub').readAsStringSync();
    final code = await runOp(api.access(e.name, 'add', who, publicKey: pub));
    if (code != 0) return code;
    final g = await Process.run('ssh', ['-G', e.host]);
    String field(String n) =>
        RegExp('^$n (.*)\$', multiLine: true).firstMatch('${g.stdout}')?[1] ??
        '';
    final hostName = field('hostname'),
        user = field('user'),
        port = field('port');
    final known = await Process.run('ssh-keyscan', [
      '-p',
      port.isEmpty ? '22' : port,
      hostName,
    ]);
    stdout.writeln('''

Store these as CI secrets:
  PODSHIP_SSH_KEY      the content of $key   (then delete the folder $out)
  PODSHIP_KNOWN_HOSTS  ${(known.stdout as String).trim().split('\n').where((x) => !x.startsWith('#')).take(1).join()}

GitHub Actions example (.github/workflows/deploy.yml):

  on: { push: { branches: [main] } }
  jobs:
    deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: subosito/flutter-action@v2
        - run: dart pub global activate --source git https://github.com/framallo/podship
        - run: |
            mkdir -p ~/.ssh && chmod 700 ~/.ssh
            echo "\${{ secrets.PODSHIP_SSH_KEY }}" > ~/.ssh/podship && chmod 600 ~/.ssh/podship
            echo "\${{ secrets.PODSHIP_KNOWN_HOSTS }}" >> ~/.ssh/known_hosts
            printf 'Host ${e.host}\\n  HostName $hostName\\n  User $user\\n  Port ${port.isEmpty ? '22' : port}\\n  IdentityFile ~/.ssh/podship\\n' >> ~/.ssh/config
        - run: podship deploy --env ${e.name} --yes --json
''');
    return 0;
  }
}
