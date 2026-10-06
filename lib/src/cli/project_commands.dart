// init, launch, doctor.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';
import '../ops/context.dart';
import '../remote/ssh.dart';
import 'base.dart';

/// Finds the Serverpod server package and the Flutter web apps under [root].
({String? server, List<String> webApps, String project}) detectProject(
  String root,
) {
  String? server;
  final web = <String>[];
  final dirs = [
    Directory(root),
    ...Directory(root).listSync().whereType<Directory>(),
  ];
  for (final d in dirs) {
    final pub = File(p.join(d.path, 'pubspec.yaml'));
    if (!pub.existsSync()) continue;
    final y = loadYaml(pub.readAsStringSync());
    if (y is! YamlMap) continue;
    final deps = y['dependencies'];
    if (deps is YamlMap && deps.containsKey('serverpod') && server == null) {
      server = p.relative(d.path, from: root);
    }
    if (deps is YamlMap &&
        deps.containsKey('flutter') &&
        Directory(p.join(d.path, 'web')).existsSync()) {
      web.add(p.relative(d.path, from: root));
    }
  }
  var project = p
      .basename(Directory(root).absolute.path)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  if (server != null && server.endsWith('_server')) {
    project = p.basename(server).replaceAll(RegExp(r'_server$'), '');
  }
  return (server: server == '.' ? '.' : server, webApps: web, project: project);
}

String configTemplate(String project, String server, List<String> webApps) {
  final web = webApps.isEmpty
      ? '  flutter_web: []\n'
      : '  flutter_web:\n${[for (final (i, w) in webApps.indexed) '    - name: ${p.basename(w)}\n'
              '      path: $w\n'
              '      output: $server/web/${i == 0 ? 'app' : p.basename(w)}\n'
              '      base_href: /${i == 0 ? 'app' : p.basename(w)}/\n'].join()}';
  String envBlock(String name, String dirName) =>
      '''
  $name:
    host: your-server            # an ssh destination or ~/.ssh/config alias
    dir: /srv/$dirName
    ports:
      api: auto                  # a free loopback port from the server registry
      web: auto
    health:
      url: "http://127.0.0.1:{port:api}/"
    secrets:
      database_password_env: POSTGRES_PASSWORD
    database:
      name: $project
    backup:
      recipients:
        - ~/.ssh/id_ed25519.pub  # who can decrypt the off-site copies
      offsite:
        dir: ~/Backups/$project-$name
    # proxy:
    #   kind: caddy              # or cloudflare_tunnel
    # domains:
    #   - host: ${name == 'production' ? '' : 'staging.'}example.com
    #     routes:
    #       - { path: "^/(api|v1)/", port: api }
    #       - { port: web }
''';
  return '''
# podship: deploy, back up and roll back this Serverpod project on your own
# servers. No secrets here: they live on the servers (`podship secret …`).
project: $project
server_package: $server

build:
  source: git                    # ship a clean export of the commit
$web  files:                        # gitignore syntax, applied last; ! includes again
${webApps.isEmpty ? '    []\n' : [for (final (i, w) in webApps.indexed) '    - "!$server/web/${i == 0 ? 'app' : p.basename(w)}/**"\n'].join()}
compose:
  files: [deploy/docker-compose.yml]

environments:
${envBlock('production', project)}${envBlock('staging', '$project-staging')}''';
}

String composeTemplate(
  String project,
  String server, {
  bool fromRoot = false,
}) =>
    '''
# Written by podship init. Each environment runs it with its own .env,
# passwords.yaml, ports and volumes.
services:
  server:
    build:
${fromRoot ? '      context: .\n      dockerfile: $server/Dockerfile' : '      context: $server'}
    restart: unless-stopped
    env_file: [.env]
    environment:
      runmode: production
      SERVERPOD_APPLY_MIGRATIONS: "true"
      SERVERPOD_DATABASE_HOST: postgres
      SERVERPOD_DATABASE_PORT: "5432"
      SERVERPOD_DATABASE_NAME: $project
      SERVERPOD_DATABASE_USER: postgres
      SERVERPOD_DATABASE_REQUIRE_SSL: "false"
    volumes:
      - ./$server/config/passwords.yaml:/app/config/passwords.yaml:ro
    ports:
      - "127.0.0.1:\${PODSHIP_PORT_API:?}:8080"
      - "127.0.0.1:\${PODSHIP_PORT_WEB:?}:8082"
    depends_on:
      postgres:
        condition: service_healthy
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_DB: $project
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD:?run podship secret init}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d $project"]
      interval: 10s
      retries: 10
volumes:
  pgdata:
''';

const _dockerfile = r'''
# Written by podship init. Build context: the server package.
FROM dart:stable AS build
WORKDIR /app
COPY . .
RUN dart pub get && dart compile exe bin/main.dart -o bin/server
RUN mkdir -p config web migrations

FROM alpine:latest
WORKDIR /app
ENV runmode=production serverid=default logging=normal role=monolith
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server bin/server
COPY --from=build /app/config/ config/
COPY --from=build /app/web/ web/
COPY --from=build /app/migrations/ migrations/
EXPOSE 8080 8081 8082
ENTRYPOINT ./bin/server --mode=$runmode --server-id=$serverid --logging=$logging --role=$role
''';

class InitCommand extends PodshipCommand {
  @override
  String get name => 'init';
  @override
  String get description =>
      'Write podship.yaml, a compose file and a Dockerfile for this Serverpod project.';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final root = Directory.current.path;
    final d = detectProject(root);
    final server =
        d.server ?? (throw Aborted('no Serverpod server package found here'));
    final files = <String, String>{
      configFileName: configTemplate(d.project, server, d.webApps),
      'deploy/docker-compose.yml': composeTemplate(
        d.project,
        server,
        // Serverpod's own Dockerfile builds from the workspace root.
        fromRoot:
            File(p.join(root, server, 'Dockerfile')).existsSync() &&
            File(
              p.join(root, server, 'Dockerfile'),
            ).readAsStringSync().contains('from the project root'),
      ),
      '.podshipignore':
          '# Like .gitignore, for what podship ships. `!pattern` includes again.\n',
      if (!File(p.join(root, server, 'Dockerfile')).existsSync())
        p.join(server, 'Dockerfile'): _dockerfile,
    };
    for (final e in files.entries) {
      final f = File(p.join(root, e.key));
      if (f.existsSync()) {
        log.info('kept ${e.key} (exists)');
        continue;
      }
      if (dryRun) {
        stdout.writeln('--- would write ${e.key}\n${e.value}');
        continue;
      }
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(e.value);
      log.ok('wrote ${e.key}');
    }
    log.info(
      'Server package: $server. Flutter web apps: ${d.webApps.isEmpty ? 'none' : d.webApps.join(', ')}.',
    );
    log.info(
      'Next: set the hosts in $configFileName, then `$exe launch --env staging`.',
    );
    return 0;
  }
}

class LaunchCommand extends PodshipCommand {
  @override
  String get name => 'launch';
  @override
  String get description =>
      'First deploy of an environment: bootstrap, register, secrets, deploy, domains, backup schedule.';
  @override
  bool get mutating => true;
  @override
  bool get destructive => true;
  @override
  Future<int> execute() async {
    final e = guardedEnv;
    final g = [
      if (yes) '--yes',
      if (globalResults?['verbose'] == true) '--verbose',
      if (globalResults?['project-dir'] != null) ...[
        '--project-dir',
        globalResults!['project-dir'] as String,
      ],
    ];
    final d = dryRun ? ['--dry-run'] : <String>[];
    final steps = <List<String>>[
      ['server', 'bootstrap', '--env', e.name, ...d],
      ['link', '--env', e.name, ...d],
      ['secret', 'init', '--env', e.name, ...d],
      if (e.database.mode == DatabaseMode.shared)
        ['db', 'provision', '--env', e.name, ...d],
      ['deploy', '--env', e.name, ...d],
      if (e.domains.isNotEmpty && e.proxy.kind != ProxyKind.none)
        ['domain', 'add', '--env', e.name, ...d],
      if (e.backup != null) ['backup', 'schedule', '--env', e.name, ...d],
    ];
    for (final s in steps) {
      log.step('$exe ${s.join(' ')}');
      final code = await runner!.run([...g, ...s]) ?? 0;
      if (code != 0) return code;
    }
    return 0;
  }
}

class DoctorCommand extends PodshipCommand {
  @override
  String get name => 'doctor';
  @override
  String get description =>
      'Check local tools, ssh, Docker on the servers, disk, ports, registry and DNS.';
  @override
  bool get takesEnv => true;

  var _fails = 0;
  void _ok(String s) => stdout.writeln('  ok    $s');
  void _warn(String s) => stdout.writeln('  warn  $s');
  void _fail(String s) {
    _fails++;
    stdout.writeln('  FAIL  $s');
  }

  @override
  Future<int> execute() async {
    stdout.writeln('Local:');
    for (final t in ['git', 'ssh', 'rsync', 'tar', 'bash']) {
      (await _has(t)) ? _ok(t) : _fail('$t is not on PATH');
    }
    final c = config;
    if (c.build.flutterWeb.isNotEmpty) {
      (await _has('flutter'))
          ? _ok('flutter')
          : _fail('flutter is needed for the web apps');
    }
    (await _has('age'))
        ? _ok('age')
        : _warn('age is not installed: `backup pull` cannot check copies');
    final envs = argResults!['env'] == null
        ? c.environments.values.toList()
        : [env];
    for (final e in envs) {
      stdout.writeln('\n${e.name} (${e.host}:${e.dir}):');
      final t0 = DateTime.now();
      String out;
      try {
        out = await ctx.query(
          e,
          r'''
echo "os $(uname -s) $(uname -m)"
echo "docker $(docker version --format '{{.Server.Version}} {{.Server.Arch}}' 2>/dev/null || echo missing)"
echo "compose $(docker compose version --short 2>/dev/null || echo missing)"
for t in curl rsync age zstd; do command -v $t >/dev/null && echo "tool $t ok" || echo "tool $t missing"; done
'''
          'df -Pk ${shq(e.dir)} 2>/dev/null | tail -1 | awk \'{print "free " \$4}\' || df -Pk / | tail -1 | awk \'{print "free " \$4}\'\n',
        );
      } on RemoteException catch (x) {
        _fail('ssh ${e.host}: ${x.stderr.trim().split('\n').last}');
        continue;
      }
      _ok('ssh in ${DateTime.now().difference(t0).inMilliseconds} ms');
      for (final line in out.trim().split('\n')) {
        if (line.startsWith('docker missing') ||
            line.startsWith('compose missing')) {
          _fail(
            '${line.split(' ').first} is missing: run `$exe server bootstrap --env ${e.name}`',
          );
        } else if (line.startsWith('tool ') && line.endsWith('missing')) {
          _warn('${line.split(' ')[1]} is missing on the server');
        } else if (line.startsWith('free ')) {
          final kb = int.tryParse(line.substring(5)) ?? 0;
          final gb = kb / 1024 / 1024;
          gb < 5
              ? _warn('only ${gb.toStringAsFixed(1)} GB free')
              : _ok('${gb.toStringAsFixed(1)} GB free');
        } else if (!line.startsWith('tool ')) {
          _ok(line);
        }
      }
      try {
        final (:state, :r) = await load(e);
        _ok(
          'registry: ports ${r.ports.entries.map((x) => '${x.key}=${x.value}').join(' ')}',
        );
        for (final port in r.ports.values) {
          final mine =
              state.registry.entries[r.entry.key]?.ports.containsValue(port) ??
              false;
          if (state.listening.contains(port) &&
              !mine &&
              state.current == null) {
            _fail('port $port is already in use on ${e.host}');
          }
        }
        state.envFileExists
            ? _ok('secrets file exists')
            : _warn('no .env yet: `$exe secret init --env ${e.name}`');
        _ok('current release: ${state.current ?? '(none)'}');
      } catch (x) {
        _fail('$x');
      }
      for (final d in e.domains) {
        try {
          final a = await InternetAddress.lookup(d.host);
          _ok('DNS ${d.host}: ${a.map((x) => x.address).join(' ')}');
        } catch (_) {
          _warn('DNS ${d.host}: no answer');
        }
      }
    }
    stdout.writeln(
      _fails == 0 ? '\nNo problems found.' : '\n$_fails problem(s).',
    );
    return _fails == 0 ? 0 : 1;
  }

  Future<bool> _has(String tool) async =>
      (await Process.run('bash', ['-c', 'command -v $tool'])).exitCode == 0;
}
