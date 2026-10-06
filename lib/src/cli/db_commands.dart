// db: connect, migrate status, users, wipe, and tunnels to services.

import 'dart:io';

import '../config/config.dart';
import '../ops/context.dart';
import '../ops/secrets.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import 'base.dart';

/// The shell expression that finds the database container of [e].
String dbContainerExpr(EnvConfig e) => e.database.mode == DatabaseMode.shared
    ? DatabaseConfig.sharedContainer
    : '\$(docker ps -q --filter label=com.docker.compose.project=${shq(e.composeProject)} '
          '--filter label=com.docker.compose.service=${shq(e.database.service)} | head -1)';

String _admin(EnvConfig e) =>
    e.database.mode == DatabaseMode.shared ? 'postgres' : e.database.user;

/// Runs SQL as the database admin and returns the output.
Future<String> sql(
  Ctx ctx,
  EnvConfig e,
  String query, {
  String? db,
}) => ctx.query(
  e,
  'c=${dbContainerExpr(e)}; [ -n "\$c" ] || { echo "no database container" >&2; exit 1; }\n'
  'docker exec -i "\$c" psql -U ${shq(_admin(e))} -d ${shq(db ?? e.database.name)} -v ON_ERROR_STOP=1 -Atq -F " | "',
  stdin: query.codeUnits,
);

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
      '${ctx.header(e)}c=${dbContainerExpr(e)}; exec docker exec -it "\$c" psql -U ${shq(_admin(e))} -d ${shq(e.database.name)}',
      tty: true,
    );
  }
}

class DbMigrateStatusCommand extends PodshipCommand {
  @override
  String get name => 'status';
  @override
  String get description =>
      'Applied Serverpod migrations per module, against the ones in the current release.';
  @override
  Future<int> execute() async {
    final e = env;
    final l = EnvLayout(e);
    final applied = await sql(
      ctx,
      e,
      'select module, version, "timestamp" from serverpod_migrations order by module;',
    );
    final shipped = await ctx.query(
      e,
      'ls -1 ${shq('${l.current}/${config.serverPackage}/migrations')} 2>/dev/null | grep -E "^[0-9]{17}" | sort | tail -1 || true',
    );
    stdout.writeln('Applied (module | version | time):');
    stdout.write(applied);
    final latest = shipped.trim();
    stdout.writeln(
      'Newest migration in the current release: ${latest.isEmpty ? '(none found)' : latest}',
    );
    final mine = applied
        .split('\n')
        .where(
          (x) => x.startsWith(
            '${config.serverPackage.replaceAll('_server', '')} |',
          ),
        )
        .map((x) => x.split(' | ')[1])
        .firstOrNull;
    if (mine != null && latest.isNotEmpty) {
      stdout.writeln(
        mine == latest
            ? 'Up to date.'
            : mine.compareTo(latest) < 0
            ? 'Pending: the server applies $latest at its next start (or run a deploy).'
            : 'The database is AHEAD of the release ($mine > $latest): it ran a newer release.',
      );
    }
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
      stdout.write(
        await sql(
          ctx,
          e,
          "select rolname, rolcanlogin, rolsuper from pg_roles where rolname !~ '^pg_' order by 1;",
        ),
      );
      return 0;
    }
    if (argResults!.rest.length != 1) usageException('give one NAME');
    final role = argResults!.rest.single;
    if (!RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch(role))
      usageException('invalid role name');
    final pw = randomSecret(24).replaceAll(RegExp(r'[^A-Za-z0-9]'), 'x');
    final db = e.database.name;
    final q = switch (_action) {
      'create' =>
        'create role "$role" login password \'$pw\';\n'
            'grant connect on database "$db" to "$role";\n'
            'grant usage on schema public to "$role";\n'
            'grant select, insert, update, delete on all tables in schema public to "$role";\n'
            'grant usage, select on all sequences in schema public to "$role";\n'
            'alter default privileges in schema public grant select, insert, update, delete on tables to "$role";\n',
      'reset-password' => 'alter role "$role" password \'$pw\';\n',
      _ =>
        'reassign owned by "$role" to "${_admin(e)}"; drop owned by "$role"; drop role "$role";\n',
    };
    await ctx.run(
      Plan('db user $_action $role on ${e.name}', [
        ActionStep(
          'Run SQL',
          'db user $_action $role (password hidden)',
          () async {
            await sql(ctx, e, q);
            if (_action != 'delete') {
              stdout.writeln(
                'Role $role on ${e.name}. Password (shown once): $pw',
              );
            }
          },
        ),
      ]),
    );
    return 0;
  }
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
    final l = EnvLayout(e);
    final db = e.database.name;
    await ctx.run(
      Plan('db wipe ${e.name}', [
        RemoteStep('Rename $db and create an empty one', e.host, '''
${ctx.header(e)}c=${dbContainerExpr(e)}
${shq(l.currentComposeSh)} stop ${shq(e.serverService)}
docker exec -i "\$c" psql -U ${shq(_admin(e))} -d postgres -v ON_ERROR_STOP=1 \\
  -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$db' and pid <> pg_backend_pid();" \\
  -c "alter database \\"$db\\" rename to \\"${db}_wiped_\$(date +%Y%m%d%H%M%S)\\";" \\
  -c "create database \\"$db\\";"
${shq(l.currentComposeSh)} up -d --no-build ${shq(e.serverService)}
'''),
      ]),
    );
    return 0;
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
