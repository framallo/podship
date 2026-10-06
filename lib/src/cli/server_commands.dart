// server, projects, destroy, domain, access, ci, link, db provision.

import 'dart:io';

import '../config/config.dart';
import '../edit/dotenv.dart';
import '../edit/passwords.dart';
import '../ops/backup_ops.dart';
import '../ops/context.dart';
import '../ops/domain_ops.dart';
import '../ops/scripts.dart';
import '../ops/secrets.dart';
import '../ops/server_ops.dart';
import '../ops/state.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
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
  Future<int> execute() async {
    final e = env;
    await ctx.run(
      Plan('bootstrap ${e.host}', [
        RemoteStep(
          'Install what is missing',
          e.host,
          bootstrapScript(
            e,
            caddy:
                argResults!['caddy'] == true || e.proxy.kind == ProxyKind.caddy,
            firewall: argResults!['firewall'] == true,
            deployUser: argResults!['user'] as String?,
          ),
        ),
      ]),
    );
    return 0;
  }
}

class ServerStatusCommand extends PodshipCommand {
  @override
  String get name => 'status';
  @override
  String get description =>
      'Every project on the server of --env: registry, containers, memory, disk.';
  @override
  Future<int> execute() async {
    final e = env;
    final state = await fetchState(ctx, e);
    stdout.writeln('Server ${e.host} — projects in ${e.registryPath}:');
    registryTable(state.registry).forEach((x) => stdout.writeln('  $x'));
    stdout.write(
      await ctx.query(e, r'''
echo
echo "Containers by compose project:"
docker ps --format '{{.Label "com.docker.compose.project"}}' | sort | uniq -c | sed 's/^/  /'
echo
echo "Memory and CPU:"
docker stats --no-stream --format '  {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | sort
echo
df -h / | tail -1 | awk '{print "Disk /: " $4 " free of " $2 " (" $5 " used)"}'
docker system df | sed 's/^/  /'
'''),
    );
    return 0;
  }
}

class ProjectsListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'The projects and environments registered on the server of --env.';
  @override
  Future<int> execute() async {
    final state = await fetchState(ctx, env);
    registryTable(state.registry).forEach(stdout.writeln);
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
  Future<int> execute() async {
    final e = env;
    final (:state, :r) = await load(e);
    final reg = state.registry..put(r.entry);
    await ctx.run(
      Plan('link ${config.project}/${e.name} on ${e.host}', [
        RemoteStep(
          'Write the registry',
          e.host,
          ctx.header(e) +
              installAssets(e) +
              writeRegistry(e, state.registryText, reg.render()),
        ),
      ]),
    );
    if (!dryRun) {
      log.info(
        'ports: ${r.ports.entries.map((x) => '${x.key}=${x.value}').join(' ')}'
        '${r.backupSchedule == null ? '' : '; backups: ${r.backupSchedule}'}',
      );
    }
    return 0;
  }
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
    final (:state, :r) = await load(e);
    final macos =
        !dryRun && (await ctx.query(e, 'uname -s')).trim() == 'Darwin';
    await ctx.run(
      planDestroy(
        ctx,
        r,
        state.registry,
        state.registryText,
        purgeBackups: argResults!['purge-backups'] == true,
        domainSteps: e.domains.isEmpty || e.proxy.kind == ProxyKind.none
            ? const []
            : planDomain(ctx, r, [
                for (final d in e.domains) d.host,
              ], remove: true).steps,
        scheduleSteps: e.backup == null
            ? const []
            : planSchedule(ctx, r, macos: macos, remove: true).steps,
      ),
    );
    return 0;
  }
}

class DomainAddCommand extends PodshipCommand {
  DomainAddCommand(this._remove);
  final bool _remove;
  @override
  String get name => _remove ? 'remove' : 'add';
  @override
  String get description => _remove
      ? 'Remove the routes of a domain from the proxy.'
      : 'Route a domain from podship.yaml to this environment (Cloudflare Tunnel or Caddy with TLS).';
  @override
  String get invocation => '$exe domain $name [HOST…] [--env <env>]';
  @override
  bool get mutating => true;
  @override
  bool get destructive => _remove;
  @override
  Future<int> execute() async {
    final e = _remove ? guardedEnv : env;
    final hosts = argResults!.rest.isEmpty
        ? [for (final d in e.domains) d.host]
        : argResults!.rest;
    if (hosts.isEmpty) {
      usageException('no domains in environments.${e.name}.domains');
    }
    final (:state, :r) = await load(e);
    await ctx.run(planDomain(ctx, r, hosts, remove: _remove));
    if (!_remove) {
      for (final h in hosts) {
        log.info('DNS for $h: ${dnsRecord(e, h)}');
      }
    }
    return 0;
  }
}

class DomainListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'Domains in podship.yaml, the routes on the proxy, and DNS answers.';
  @override
  Future<int> execute() async {
    final e = env;
    final (:state, :r) = await load(e);
    for (final d in r.domains.entries) {
      List<InternetAddress> addrs = const [];
      try {
        addrs = await InternetAddress.lookup(d.key);
      } catch (_) {}
      stdout.writeln(
        '${d.key}: ${d.value.map((x) => '${x.path ?? '/'} → ${x.port}').join(', ')}'
        '  DNS: ${addrs.isEmpty ? 'no answer' : addrs.map((a) => a.address).join(' ')}',
      );
      stdout.writeln('  needs: ${dnsRecord(e, d.key)}');
    }
    if (e.proxy.kind == ProxyKind.cloudflareTunnel && e.proxy.config != null) {
      stdout.writeln('Tunnel rules on ${e.host}:');
      for (final rule in tunnelRules(
        await readRemote(ctx, e, e.proxy.config!),
      )) {
        stdout.writeln('  $rule');
      }
    }
    return 0;
  }
}

class DbProvisionCommand extends PodshipCommand {
  @override
  String get name => 'provision';
  @override
  String get description =>
      'Shared-Postgres mode: start podship-postgres once per server, create this environment\'s database and role, store the credentials.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    if (e.database.mode != DatabaseMode.shared) {
      throw Aborted(
        '${e.name} uses its own Postgres (database.mode: per_env); nothing to provision',
      );
    }
    final l = EnvLayout(e);
    await ctx.run(
      Plan('provision ${e.database.name} in the shared Postgres on ${e.host}', [
        ActionStep(
          'Create database and role',
          '${e.database.name} owned by ${e.database.user}; password stored as a secret (hidden)',
          () async {
            final out = await ctx.query(e, sharedDbScript(e));
            final pw = RegExp(
              r'PODSHIP_DB_PASSWORD=(\S+)',
            ).firstMatch(out)![1]!;
            final p = PasswordsFile(await readRemote(ctx, e, l.passwordsFile))
              ..set(e.runMode, 'database', pw);
            await writeRemote(ctx, e, l.passwordsFile, p.toString());
            final f = DotEnv(await readRemote(ctx, e, l.envFile))
              ..set(
                'SERVERPOD_DATABASE_HOST',
                DatabaseConfig.sharedContainer,
                plain: true,
              )
              ..set('SERVERPOD_DATABASE_PORT', '5432', plain: true)
              ..set('SERVERPOD_DATABASE_NAME', e.database.name, plain: true)
              ..set('SERVERPOD_DATABASE_USER', e.database.user, plain: true)
              ..set('SERVERPOD_DATABASE_REQUIRE_SSL', 'false', plain: true);
            await writeRemote(ctx, e, l.envFile, f.toString());
          },
        ),
      ]),
    );
    return 0;
  }
}

/// The marker podship puts on the keys it manages in authorized_keys.
String accessTag(String name) => 'podship:$name';

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
    'remove' => 'Remove a person\'s key from the server of --env.',
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
      stdout.write(
        await ctx.query(
          e,
          r'''grep -o 'podship:[A-Za-z0-9._@-]*' ~/.ssh/authorized_keys 2>/dev/null | sed 's/^podship://' || true''',
        ),
      );
      return 0;
    }
    if (argResults!.rest.length != 1) usageException('give one NAME');
    final who = argResults!.rest.single;
    if (!RegExp(r'^[A-Za-z0-9._@-]+$').hasMatch(who)) {
      usageException('invalid NAME');
    }
    String script;
    if (_action == 'add') {
      final k = argResults!['key'] as String;
      final f = File(expandHome(k));
      final key = (f.existsSync() ? f.readAsStringSync() : k)
          .trim()
          .split('\n')
          .first;
      final parts = key.split(RegExp(r'\s+'));
      if (parts.length < 2 || !isPublicKey(key)) {
        throw Aborted('not a public key: $k');
      }
      final line = '${parts[0]} ${parts[1]} ${accessTag(who)}';
      script =
          '''
umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys
grep -v ${shq(' ${accessTag(who)}\$')} ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.podship-tmp || true
echo ${shq(line)} >> ~/.ssh/authorized_keys.podship-tmp
mv -f ~/.ssh/authorized_keys.podship-tmp ~/.ssh/authorized_keys
echo "added $who"
''';
    } else {
      script =
          '''
grep -v ${shq(' ${accessTag(who)}\$')} ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.podship-tmp || true
mv -f ~/.ssh/authorized_keys.podship-tmp ~/.ssh/authorized_keys
echo "removed $who"
''';
    }
    await ctx.run(
      Plan('access $_action $who on ${e.host}', [
        RemoteStep('Edit ~/.ssh/authorized_keys', e.host, script),
      ]),
    );
    return 0;
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
        ? 'ssh-ed25519 AAAA… podship-$who'
        : File('$key.pub').readAsStringSync().trim();
    final line = '${pub.split(' ').take(2).join(' ')} ${accessTag(who)}';
    await ctx.run(
      Plan('ci setup on ${e.host}', [
        RemoteStep('Authorize the CI key', e.host, '''
umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys
grep -v ${shq(' ${accessTag(who)}\$')} ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.podship-tmp || true
echo ${shq(line)} >> ~/.ssh/authorized_keys.podship-tmp
mv -f ~/.ssh/authorized_keys.podship-tmp ~/.ssh/authorized_keys
'''),
      ]),
    );
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
        - run: podship deploy --env ${e.name} --yes
''');
    return 0;
  }
}
