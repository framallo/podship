// End-to-end test against a real server with Docker, over ssh.
//
//   PODSHIP_IT_HOST=user@host [PODSHIP_IT_HOME=/srv/podship-it] \
//   [PODSHIP_IT_PATH=/opt/homebrew/bin] dart test test/integration
//
// It builds a tiny project (a Python web server and Postgres), then runs
// deploy, a failed deploy with automatic rollback, rollback, rollback --to,
// backup now/list/drill/restore, promote and destroy, all through the CLI.
// Everything lives in its own compose projects and folders, and it removes
// them at the end. Without PODSHIP_IT_HOST the test is skipped.
@Tags(['integration'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/podship.dart';
import 'package:test/test.dart';

final host = Platform.environment['PODSHIP_IT_HOST'];
final home = Platform.environment['PODSHIP_IT_HOME'] ?? '/srv/podship-it';
final remotePath = Platform.environment['PODSHIP_IT_PATH'];
final pubKey =
    Platform.environment['PODSHIP_IT_PUBKEY'] ?? '~/.ssh/id_ed25519.pub';

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

String compose() => r'''
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

String config() =>
    '''
project: podship-it
server_package: server
compose: {files: [docker-compose.yml]}
environments:
${['staging', 'production'].map((e) => '''
  $e:
    host: $host
    dir: $home/podship-it-$e
    podship_home: $home
${remotePath == null ? '' : '    remote_path: "$remotePath"\n'}    ports: {web: auto}
    health: {url: "http://127.0.0.1:{port:web}/health", attempts: 10, interval: 2}
    secrets: {generate: [POSTGRES_PASSWORD]}
    database: {name: it}
    releases: {keep: 3}
    backup:
      dir: $home/backups/podship-it-$e
      compression: gzip
      recipients: ["$pubKey"]
''').join()}''';

void main() {
  if (host == null) {
    test(
      'integration (set PODSHIP_IT_HOST)',
      () {},
      skip: 'PODSHIP_IT_HOST is not set',
    );
    return;
  }
  group('podship on $host', timeout: const Timeout(Duration(minutes: 30)), () {
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
      final r = await Process.run('ssh', [
        host!,
        'bash -c ${_q('${remotePath == null ? '' : 'export PATH="$remotePath:\$PATH"; '}$script')}',
      ]);
      if (r.exitCode != 0) throw Exception('ssh: ${r.stderr}');
      return (r.stdout as String).trim();
    }

    String current(String env) => '$home/podship-it-$env/current';
    Future<String> currentId(String env) async =>
        p.basename(await sh('readlink ${current(env)}'));
    Future<String> psql(String sql) => sh(
      'docker exec -i \$(docker ps -q --filter label=com.docker.compose.project=podship-it-staging --filter label=com.docker.compose.service=postgres) psql -U postgres -d it -Atqc ${_q(sql)}',
    );

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('podship-it-');
      File(p.join(dir.path, 'podship.yaml')).writeAsStringSync(config());
      File(p.join(dir.path, 'docker-compose.yml')).writeAsStringSync(compose());
      Directory(p.join(dir.path, 'server')).createSync();
      File(p.join(dir.path, 'server', 'app.py')).writeAsStringSync(appPy);
      File(p.join(dir.path, 'server', 'Dockerfile')).writeAsStringSync(
        'FROM python:3.12-alpine\nWORKDIR /app\nCOPY . .\nCMD ["python", "app.py"]\n',
      );
      await git(['init', '-q', '-b', 'main']);
      await git(['config', 'user.email', 'it@podship.dev']);
      await git(['config', 'user.name', 'podship it']);
    });

    tearDownAll(() async {
      for (final e in ['staging', 'production']) {
        await podship([
          'destroy',
          '--env',
          e,
          '--confirm',
          'podship-it',
          '--purge-backups',
        ]);
      }
      await dir.delete(recursive: true);
    });

    test('deploy, auto-rollback, rollback, backups, promote', () async {
      final t = Stopwatch()..start();
      void mark(String s) => stdout.writeln('[${t.elapsed.inSeconds}s] $s');

      await commit('v1');
      expect(await podship(['link', '--env', 'staging']), 0);
      expect(await podship(['secret', 'init', '--env', 'staging']), 0);
      expect(await podship(['deploy', '--env', 'staging']), 0);
      final v1 = await currentId('staging');
      mark('v1 = $v1');

      await psql(
        'create table item (id serial primary key, name text); insert into item (name) values (\'a\'), (\'b\'), (\'c\');',
      );
      expect(await podship(['backup', 'now', '--env', 'staging']), 0);
      final list = await sh('ls -1 $home/backups/podship-it-staging/daily');
      final stamp = list.split('\n').last;
      expect(
        await sh('ls $home/backups/podship-it-staging/encrypted'),
        contains('$stamp.tar.age'),
      );
      expect(await podship(['backup', 'drill', '--env', 'staging']), 0);
      mark('backup $stamp and drill ok');

      await commit('v2', broken: true);
      expect(
        await podship(['deploy', '--env', 'staging', '--skip-backup']),
        isNot(0),
      );
      expect(
        await currentId('staging'),
        v1,
        reason: 'a failed health check switches back',
      );
      mark('broken v2 rolled back to v1');

      await commit('v3');
      expect(await podship(['deploy', '--env', 'staging', '--skip-backup']), 0);
      final v3 = await currentId('staging');
      expect(v3, isNot(v1));
      expect(await podship(['rollback', '--env', 'staging']), 0);
      expect(await currentId('staging'), v1);
      expect(await podship(['rollback', '--env', 'staging', '--to', v3]), 0);
      expect(await currentId('staging'), v3);
      mark('rollback and roll forward ok');

      await psql('insert into item (name) values (\'d\')');
      expect(await psql('select count(*) from item'), '4');
      expect(
        await podship([
          'backup',
          'restore',
          stamp,
          '--env',
          'staging',
          '--confirm',
          'podship-it',
        ]),
        0,
      );
      expect(await psql('select count(*) from item'), '3');
      mark('restore ok');

      expect(
        await podship(['env', 'set', 'GREETING=hola', '--env', 'staging']),
        0,
      );
      expect(
        await sh('grep GREETING ${'$home/podship-it-staging/shared/.env'}'),
        'GREETING=hola',
      );

      expect(await podship(['secret', 'init', '--env', 'production']), 0);
      expect(await podship(['promote', 'staging', 'production']), 0);
      expect(await currentId('production'), v3);
      mark('promote ok');
      expect(await podship(['status', '--env', 'production']), 0);
    });
  });
}

String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";
