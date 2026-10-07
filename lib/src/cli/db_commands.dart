import 'dart:async';
// db: connect, provision, wipe, migrate status, users; and tunnel.

import 'dart:io';

import '../ops/db_ops.dart';
import '../remote/ssh.dart';
import '../protocol/protocol.dart';
import 'base.dart';

class DbConnectCommand extends PodshipCommand {
  @override
  String get name => 'connect';
  @override
  String get description =>
      'Open psql on the environment database (through ssh).';
  @override
  Future<int> execute() async {
    final e = env;
    return ctx.ssh.stream(
      e.host,
      '${ctx.header(e)}c=${dbContainerExpr(e)}; exec docker exec -it "\$c" psql -U ${shq(dbAdmin(e))} -d ${shq(e.database.name)}',
      tty: true,
    );
  }
}

class DbMigrateStatusCommand extends PodshipCommand {
  @override
  OperationRequest? get consoleRead => request('db.migrate.status');
  @override
  String get name => 'status';
  @override
  String get description =>
      'Applied Serverpod migrations per module, against the ones in the current release.';
  @override
  Future<int> execute() async {
    final s = await api.migrateStatus(env.name);
    if (json) {
      printJson(s.toJson());
      return 0;
    }
    stdout.writeln('Applied (module | version | time):');
    for (final a in s.applied) {
      stdout.writeln('  ${a['module']} | ${a['version']} | ${a['time'] ?? ''}');
    }
    stdout.writeln(
      'Newest migration in the current release: ${s.newestShipped ?? '(none found)'}',
    );
    stdout.writeln(switch (s.state) {
      'up_to_date' => 'Up to date.',
      'pending' =>
        'Pending: the server applies ${s.newestShipped} at its next start.',
      'ahead' =>
        'The database is AHEAD of the release (${s.appliedVersion} > ${s.newestShipped}): it ran a newer release.',
      _ => 'Cannot compare.',
    });
    return 0;
  }
}

class DbUserCommand extends PodshipCommand {
  DbUserCommand(this._action);
  final String _action;
  @override
  String get name => _action;
  @override
  String get description => switch (_action) {
    'create' =>
      'Create a database role with read and write access. Prints its password once.',
    'reset-password' => 'Give a role a new password. Prints it once.',
    'delete' => 'Delete a role.',
    _ => 'List roles.',
  };
  @override
  String get invocation =>
      '$exe db user $_action${_action == 'list' ? '' : ' NAME'} [--env <env>]';
  @override
  bool get mutating => _action != 'list';
  @override
  bool get destructive => _action == 'delete';

  @override
  Future<int> execute() async {
    final e = _action == 'delete' ? guardedEnv : env;
    if (_action == 'list') {
      final out = await sql(
        ctx,
        e,
        "select rolname, rolcanlogin, rolsuper from pg_roles where rolname !~ '^pg_' order by 1;",
      );
      json
          ? printJson([
              for (final l in out.trim().split('\n'))
                if (l.contains(' | '))
                  {
                    'role': l.split(' | ')[0],
                    'login': l.split(' | ')[1] == 't',
                    'superuser': l.split(' | ')[2] == 't',
                  },
            ])
          : stdout.write(out);
      return 0;
    }
    if (argResults!.rest.length != 1) usageException('give one NAME');
    final op = api.dbUser(e.name, _action, argResults!.rest.single);
    final code = await runOp(op);
    // Through a console the operation ran there; reading op.result here
    // would run it a second time.
    if (via == 'console') return code;
    final r = await op.result;
    if (code == 0 && !json && r.data['password'] != null) {
      stdout.writeln('Password (shown once): ${r.data['password']}');
    }
    return code;
  }
}

class DbProvisionCommand extends PodshipCommand {
  @override
  String get name => 'provision';
  @override
  String get description =>
      "Shared-Postgres mode: start podship-postgres once per server, create this environment's database and role, store the credentials.";
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async => runOp(api.dbProvision(env.name));
}

class DbWipeCommand extends PodshipCommand {
  DbWipeCommand() {
    argParser.addOption(
      'confirm',
      help: 'The project name, to confirm without a terminal.',
    );
  }
  @override
  String get name => 'wipe';
  @override
  String get description =>
      'Start from an empty database. The current one is renamed, not dropped; restart applies migrations.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    ctx.typeProjectName(
      'This empties the ${e.name} database of ${config.project}.',
      typed: argResults!['confirm'] as String?,
    );
    return runOp(api.dbWipe(e.name));
  }
}

class TunnelCommand extends PodshipCommand {
  TunnelCommand() {
    argParser
      ..addOption('service', defaultsTo: 'server', help: 'The compose service.')
      ..addOption(
        'port',
        defaultsTo: '8081',
        help: 'The port inside the service (8081 is Serverpod Insights).',
      )
      ..addOption('local', help: 'The local port (default: same as --port).');
  }
  @override
  String get name => 'tunnel';
  @override
  String get description =>
      'Forward a local port to a service port that is not published (Insights, Postgres…). Ctrl+C ends it.';
  @override
  Future<int> execute() async {
    final e = env;
    final a = argResults!;
    final port = int.parse(a['port'] as String);
    final local = int.parse(a['local'] as String? ?? '$port');
    final service = a['service'] as String;
    final name = 'podship-tunnel-${e.composeProject}-$service-$port';
    // A small socat container joins the service's network and publishes
    // the port on the server's loopback only, on a random free port.
    final remotePort = await ctx.query(e, '''
c=\$(docker ps -q --filter label=com.docker.compose.project=${shq(e.composeProject)} --filter label=com.docker.compose.service=${shq(service)} | head -1)
[ -n "\$c" ] || { echo "no running $service" >&2; exit 1; }
net=\$(docker inspect -f '{{range \$k, \$v := .NetworkSettings.Networks}}{{\$k}} {{end}}' "\$c" | awk '{print \$1}')
ip=\$(docker inspect -f "{{(index .NetworkSettings.Networks \\"\$net\\").IPAddress}}" "\$c")
docker rm -f ${shq(name)} >/dev/null 2>&1 || true
docker run -d --rm --name ${shq(name)} --network "\$net" -p 127.0.0.1::$port alpine/socat tcp-listen:$port,fork,reuseaddr "tcp-connect:\$ip:$port" >/dev/null
docker port ${shq(name)} $port/tcp | head -1 | sed 's/.*://'
''');
    if (isLocalHost(e.host)) {
      // The server is this machine: the socat port is the forward.
      log.info(
        'Forwarding localhost:${remotePort.trim()} → $service:$port. Ctrl+C to stop.',
      );
      final done = Completer<void>();
      final sub = ProcessSignal.sigint.watch().listen((_) {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      await sub.cancel();
      await ctx.query(e, 'docker rm -f ${shq(name)} >/dev/null 2>&1 || true');
      return 0;
    }
    log.info(
      'Forwarding localhost:$local → $service:$port on ${e.host}. Ctrl+C to stop.',
    );
    final proc = await Process.start('ssh', [
      ...ctx.ssh.options(),
      '-N',
      '-L',
      '$local:127.0.0.1:${remotePort.trim()}',
      e.host,
    ], mode: ProcessStartMode.inheritStdio);
    ProcessSignal.sigint.watch().listen((_) => proc.kill());
    final code = await proc.exitCode;
    await ctx.query(e, 'docker rm -f ${shq(name)} >/dev/null 2>&1 || true');
    return code;
  }
}
