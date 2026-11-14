// Blue/green end to end, with real Docker, on PODSHIP_IT_HOST (`local` for
// this machine's Docker, or user@host over ssh):
//
//   PODSHIP_IT_HOST=local dart run tool/test.dart integration \
//     -n 'blue/green'
//
// A tiny project (a Python web server and Postgres holding rows) goes
// through: an in-place deploy, the first blue/green deploy (conversion), a
// flip, `compose.sh up -d postgres` with a color active, a failure before
// the flip (the new color fails its pre-flip check), a failure after the
// flip (the public URL fails; the front flips back), a destructive
// migration that stops the deploy, and leaving blue/green with
// --allow-destructive-migrations. After each step: the rows are all there,
// there is exactly one Postgres container, and it was never recreated.
// With `local`, PODSHIP_IT_HOME defaults to ~/.podship-bg-it (Colima mounts
// only the home folder into its VM).
@Tags(['integration'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/podship.dart';
import 'package:test/test.dart';

final host = Platform.environment['PODSHIP_IT_HOST'];
final home =
    Platform.environment['PODSHIP_IT_HOME'] ??
    (host == 'local'
        ? '${Platform.environment['HOME']}/.podship-bg-it'
        : '/srv/podship-it');
final remotePath = Platform.environment['PODSHIP_IT_PATH'];

const project = 'podship-bg';
const cp = '$project-staging';

const appPy = r'''
import http.server, os
VERSION = open("/app/VERSION").read().strip()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        broken = os.path.exists("/app/BROKEN")
        code = 500 if broken and self.path == "/health" else 200
        body = (VERSION + "\n").encode()
        self.send_response(code); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("0.0.0.0", 8082), H).serve_forever()
''';

const composeYml = r'''
services:
  server:
    build: {context: server}
    restart: unless-stopped
    env_file: [.env]
    ports: ["127.0.0.1:${PODSHIP_PORT_WEB:?}:8082"]
    depends_on: {postgres: {condition: service_healthy}}
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_DB: it
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?}
    volumes: [pgdata:/var/lib/postgresql/data]
    healthcheck: {test: ["CMD-SHELL", "pg_isready -U postgres -d it"], interval: 2s, retries: 30}
volumes:
  pgdata:
''';

String config({required bool blueGreen, String? publicUrl}) =>
    '''
project: $project
server_package: server
compose: {files: [docker-compose.yml]}
environments:
  staging:
    host: $host
    dir: $home/$cp
    podship_home: $home
${remotePath == null ? '' : '    remote_path: "$remotePath"\n'}    ports: {web: auto}
    health:
      url: "http://127.0.0.1:{port:web}/health"
${publicUrl == null ? '' : '      public_url: "$publicUrl"\n'}      attempts: 5
      interval: 2
    secrets: {generate: [POSTGRES_PASSWORD]}
    database: {name: it}
    releases: {keep: 5}
${blueGreen ? '    switch: blue_green\n    blue_green: {drain: 2}\n' : ''}''';

void main() {
  if (host == null) {
    test(
      'blue/green integration (set PODSHIP_IT_HOST)',
      () {},
      skip: 'PODSHIP_IT_HOST is not set',
    );
    return;
  }
  group('blue/green on $host', () {
    late Directory dir;

    Future<int> podship(List<String> args) async {
      stdout.writeln('\$ podship ${args.join(' ')}');
      return await PodshipRunner().run([
            '--yes',
            '--project-dir',
            dir.path,
            ...args,
          ]) ??
          0;
    }

    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: dir.path);
      if (r.exitCode != 0) {
        throw Exception('git ${args.join(' ')}: ${r.stderr}');
      }
    }

    void writeConfig({required bool blueGreen, String? publicUrl}) => File(
      p.join(dir.path, 'podship.yaml'),
    ).writeAsStringSync(config(blueGreen: blueGreen, publicUrl: publicUrl));

    void migration(String name, String sql) {
      final d = Directory(p.join(dir.path, 'server', 'migrations', name))
        ..createSync(recursive: true);
      File(p.join(d.path, 'migration.sql')).writeAsStringSync(sql);
    }

    Future<void> commit(String version, {bool broken = false}) async {
      File(p.join(dir.path, 'server', 'VERSION')).writeAsStringSync(version);
      final b = File(p.join(dir.path, 'server', 'BROKEN'));
      broken
          ? b.writeAsStringSync('1')
          : (b.existsSync() ? b.deleteSync() : null);
      await git(['add', '-A']);
      await git(['commit', '-qm', version]);
    }

    Future<String> sh(String script) async {
      final full =
          '${remotePath == null ? '' : 'export PATH="$remotePath:\$PATH"; '}$script';
      final r = host == 'local'
          ? await Process.run('bash', ['-c', full])
          : await Process.run('ssh', [host!, 'bash -c ${_q(full)}']);
      if (r.exitCode != 0) throw Exception('$script: ${r.stderr}');
      return (r.stdout as String).trim();
    }

    Future<List<String>> postgresContainers() async => (await sh(
      'docker ps -q --no-trunc --filter label=com.docker.compose.service=postgres '
      '--filter label=com.docker.compose.project=$cp; '
      'docker ps -q --no-trunc --filter label=com.docker.compose.service=postgres '
      '--filter label=com.docker.compose.project=$cp-blue; '
      'docker ps -q --no-trunc --filter label=com.docker.compose.service=postgres '
      '--filter label=com.docker.compose.project=$cp-green',
    )).split('\n').where((x) => x.trim().isNotEmpty).toList();

    Future<String> psql(String sql) => sh(
      'docker exec -i \$(docker ps -q --filter label=com.docker.compose.project=$cp '
      '--filter label=com.docker.compose.service=postgres) '
      'psql -U postgres -d it -Atqc ${_q(sql)}',
    );

    Future<String> served() async {
      final port = await sh(
        "grep -o 'PODSHIP_PORT_WEB=[0-9]*' $home/$cp/current/.podship/compose.sh | cut -d= -f2",
      );
      return sh('curl -s http://127.0.0.1:${port.split('\n').last.trim()}/');
    }

    Future<String> active() =>
        sh('cat $home/$cp/.podship/active-project 2>/dev/null || true');

    late String pg; // the one Postgres container
    Future<void> invariant(String step) async {
      final c = await postgresContainers();
      expect(c, hasLength(1), reason: '$step: one Postgres container');
      expect(c.single, pg, reason: '$step: Postgres was never recreated');
      expect(await psql('select count(*) from item'), '3', reason: step);
    }

    setUpAll(() async {
      await sh('mkdir -p $home');
      dir = await Directory.systemTemp.createTemp('podship-bg-it-');
      writeConfig(blueGreen: false);
      File(
        p.join(dir.path, 'docker-compose.yml'),
      ).writeAsStringSync(composeYml);
      Directory(p.join(dir.path, 'server')).createSync();
      File(p.join(dir.path, 'server', 'app.py')).writeAsStringSync(appPy);
      File(p.join(dir.path, 'server', 'Dockerfile')).writeAsStringSync(
        'FROM python:3.12-alpine\nWORKDIR /app\nCOPY . .\nCMD ["python", "app.py"]\n',
      );
      migration(
        '20261101000000000',
        'BEGIN;\nCREATE TABLE "item" ("id" bigserial PRIMARY KEY, "name" text);\nCOMMIT;\n',
      );
      await git(['init', '-q', '-b', 'main']);
      await git(['config', 'user.email', 'it@podship.dev']);
      await git(['config', 'user.name', 'podship it']);
    });

    tearDownAll(() async {
      await podship(['destroy', '--env', 'staging', '--confirm', project]);
      final left = await sh(
        'docker ps -aq --filter label=com.docker.compose.project=$cp; '
        'docker ps -aq --filter label=com.docker.compose.project=$cp-blue; '
        'docker ps -aq --filter label=com.docker.compose.project=$cp-green; '
        'docker ps -aq --filter name=$cp-front; '
        'docker network ls -q --filter name=$cp',
      );
      expect(
        left,
        isEmpty,
        reason: 'destroy removes every container and network',
      );
      await dir.delete(recursive: true);
    });

    test('conversion, flips, failures, compose.sh, leaving', () async {
      final t = Stopwatch()..start();
      void mark(String s) => stdout.writeln('[${t.elapsed.inSeconds}s] $s');

      // 1. In place, with data.
      await commit('v1');
      expect(await podship(['link', '--env', 'staging']), 0);
      expect(await podship(['secret', 'init', '--env', 'staging']), 0);
      expect(await podship(['deploy', '--env', 'staging']), 0);
      await psql(
        'create table if not exists item (id bigserial primary key, name text); '
        "insert into item (name) values ('a'), ('b'), ('c');",
      );
      pg = (await postgresContainers()).single;
      expect(await served(), 'v1');
      await invariant('in place');
      mark('v1 in place');

      // 2. First blue/green deploy: conversion.
      writeConfig(blueGreen: true);
      await commit('v2');
      expect(await podship(['deploy', '--env', 'staging']), 0);
      expect(await active(), '$cp-blue');
      expect(await served(), 'v2');
      await invariant('conversion');
      mark('v2: converted to blue');

      // 3. A flip.
      await commit('v3');
      expect(await podship(['deploy', '--env', 'staging']), 0);
      expect(await active(), '$cp-green');
      expect(await served(), 'v3');
      await invariant('flip');
      mark('v3: green');

      // 4. compose.sh names the stable service: it goes to the base
      // project, and the active color still reaches it.
      await sh('$home/$cp/current/.podship/compose.sh up -d postgres');
      await sh('$home/$cp/current/.podship/compose.sh ps');
      await invariant('compose.sh up -d postgres');
      final onNet = await sh(
        "docker network inspect -f '{{range \$k, \$v := .Containers}}{{\$k}} {{end}}' $cp-green-net",
      );
      expect(onNet, contains(pg));
      mark('compose.sh up -d postgres: still one Postgres');

      // restart: the whole release, blue/green (the other color).
      final v3 = p.basename(await sh('readlink $home/$cp/current'));
      expect(await podship(['restart', '--env', 'staging']), 0);
      expect(await active(), '$cp-blue');
      expect(await served(), 'v3');
      await invariant('restart');
      mark('restart: v3 again, now blue');

      // rollback (the migrations are checked on the server), then forward.
      expect(await podship(['rollback', '--env', 'staging']), 0);
      expect(await active(), '$cp-green');
      expect(await served(), 'v2');
      await invariant('rollback');
      expect(await podship(['rollback', '--env', 'staging', '--to', v3]), 0);
      expect(await active(), '$cp-blue');
      expect(await served(), 'v3');
      await invariant('rollback --to');
      mark('rollback to v2 and forward to v3: blue');
      final live = await active();

      // 5. Failure before the flip: the new color fails /health inside.
      await commit('v4', broken: true);
      expect(await podship(['deploy', '--env', 'staging']), isNot(0));
      expect(await active(), live);
      expect(await served(), 'v3');
      await invariant('failure before the flip');
      mark('v4 broken: the front stayed');

      // 6. Failure after the flip: the public URL fails; flip back.
      writeConfig(blueGreen: true, publicUrl: 'http://127.0.0.1:1/health');
      await commit('v5');
      expect(await podship(['deploy', '--env', 'staging']), isNot(0));
      expect(await active(), live);
      expect(await served(), 'v3');
      await invariant('failure after the flip');
      mark('v5: flipped back');
      writeConfig(blueGreen: true);

      // 7. A destructive migration stops the deploy before the upload.
      migration(
        '20261114000000000',
        'BEGIN;\nALTER TABLE "item" DROP COLUMN "name";\nCOMMIT;\n',
      );
      await commit('v6');
      expect(await podship(['deploy', '--env', 'staging']), isNot(0));
      expect(await active(), live);
      expect(await served(), 'v3');
      await invariant('destructive migration stopped');
      mark('v6: stopped on the destructive migration');

      // 8. --allow-destructive-migrations: leaves blue/green, in place.
      expect(
        await podship([
          'deploy',
          '--env',
          'staging',
          '--allow-destructive-migrations',
        ]),
        0,
      );
      expect(await active(), isEmpty);
      expect(await served(), 'v6');
      expect(await sh('docker ps -q --filter name=$cp-front'), isEmpty);
      await invariant('left blue/green');
      mark('v6 in place: left blue/green');
    });
  });
}

String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";
