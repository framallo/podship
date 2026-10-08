@Tags(['unit'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/scripts.dart';
import 'package:podship/src/release/layout.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/server/registry.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final config = PodshipConfig.parse(sampleConfig);
  final prod = resolveEnv(config, config.env('production'), Registry());

  test('the backup settings file has the layout and no secret values', () {
    final conf = backupConf(config, prod);
    expect(conf, contains('PROJECT=demo'));
    expect(conf, contains("VOLUMES='worker|demo_worker|q.db||'"));
    expect(conf, contains("DRILL_TABLES='user* ticket'"));
    expect(
      conf,
      contains('RECIPIENTS_FILE=/srv/podship/etc/demo-backup.recipients'),
    );
    expect(
      conf,
      contains(
        "SECRET_FILES='/srv/demo/shared/.env|env /srv/demo/shared/passwords.yaml|passwords.yaml'",
      ),
    );
  });

  test(
    'backup now falls back to the podship agent when no systemd unit exists',
    () {
      final script = backupNow(prod.env);
      expect(script, contains('systemctl cat demo-backup.service'));
      expect(
        script,
        contains(
          '/srv/podship/bin/podship agent backup --conf /srv/podship/etc/demo-backup.conf',
        ),
      );
      expect(script, isNot(contains('backup.sh')));
    },
  );

  test('writeFile survives content that contains the heredoc tag', () async {
    final dir = Directory.systemTemp.createTempSync('podship-wf-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = p.join(dir.path, 'a', 'f.txt');
    const content = "line 'quoted' \$HOME\nPODSHIP_EOF\nend";
    final r = await Process.run('/bin/bash', [
      '-c',
      writeFile(target, content, mode: '600'),
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(File(target).readAsStringSync(), '$content\n');
  });

  test('portable helpers switch a symlink atomically on this system', () async {
    final dir = Directory.systemTemp.createTempSync('podship-ln-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory(p.join(dir.path, 'releases', 'a')).createSync(recursive: true);
    Directory(p.join(dir.path, 'releases', 'b')).createSync(recursive: true);
    final r = await Process.run('/bin/bash', [
      '-c',
      '''
$portableHelpers
cd ${shq(dir.path)}
ln -sfn releases/a current
ln -sfn releases/b current.new && _mvlink current.new current
readlink current
_cplink releases/a releases/c && ls releases
''',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, startsWith('releases/b\n'));
    expect(r.stdout, contains('c'));
  });

  group('release files', () {
    const compose = '''
services:
  server:
    build: {context: .}
  worker:
    build: ../worker
  postgres:
    image: postgres:16-alpine
''';
    test('builtServices finds services with a build', () {
      expect(builtServices([compose]), ['server', 'worker']);
      expect(allServices([compose]), ['postgres', 'server', 'worker']);
    });
    test(
      'the override pins built images to the release and moves build contexts',
      () {
        final o = overrideYaml(
          composeProject: 'demo-staging',
          release: 'R',
          built: ['server', 'worker'],
          buildContexts: {'worker': '/srv/worker'},
        );
        expect(o, contains('"image": "demo-staging-server:R"'));
        expect(o, contains('"context": "/srv/worker"'));
        expect(o, isNot(contains('postgres')));
      },
    );
    test('the server gets the release and its commit', () {
      final o = overrideYaml(
        composeProject: 'x',
        release: 'R1',
        built: ['server'],
        serverService: 'server',
        commit: 'abc1234def',
      );
      expect(o, contains('"PODSHIP_COMMIT": "abc1234def"'));
      expect(o, contains('"PODSHIP_RELEASE": "R1"'));
      final none = overrideYaml(composeProject: 'x', release: 'R', built: []);
      expect(none, isNot(contains('PODSHIP_COMMIT')));
    });
    test('the shared database network is attached to the server', () {
      final o = overrideYaml(
        composeProject: 'x',
        release: 'R',
        built: ['server'],
        sharedNetwork: 'podship-shared',
        serverService: 'server',
      );
      expect(o, contains('external: true'));
      expect(o, contains('"networks": ["default","podship-shared"]'));
    });
    test(
      'replicas add serverless replicas, a sticky load balancer and Redis',
      () {
        final o = overrideYaml(
          composeProject: 'p',
          release: 'R',
          built: ['server'],
          extras: OverrideExtras(
            serverEnv: {'SERVERPOD_SESSION_LOG_RETENTION_PERIOD': '30d'},
            stopGraceSeconds: 30,
            replicas: 3,
            serverPorts: ['127.0.0.1:20001:8082'],
            extendsFile: '/r/docker-compose.yml',
            egressProxy: 'socks5://mx:1080',
            egressServices: ['chrome'],
          ),
        );
        expect(o, contains('"ports": !reset []'));
        expect(o, contains('"server-replica":'));
        expect(o, contains('"replicas": 2'));
        expect(o, contains('"SERVERPOD_SERVER_ROLE": "serverless"'));
        expect(o, contains('"podship-lb":'));
        expect(o, contains('"redis":'));
        expect(o, contains('"PODSHIP_CHROME_PROXY": "socks5://mx:1080"'));
        expect(o, contains('"stop_grace_period": "30s"'));
        expect('\n'.allMatches(o).length, greaterThan(20));
        expect(
          lbConfig([8080, 8082]),
          contains('ip_hash; server server:8082; server server-replica:8082;'),
        );
        expect(containerPort('127.0.0.1:\${PUERTO_WEB:-8082}:8082'), 8082);
      },
    );
    test('compose.sh passes the project, the files and the ports', () {
      final s = composeSh(
        composeProject: 'demo',
        releaseDir: '/srv/demo/releases/R',
        composeFiles: ['docker-compose.yml'],
        ports: {'web': 20000},
      );
      expect(s, contains('export PODSHIP_PORT_WEB=20000'));
      expect(
        s,
        contains(
          '-p demo --project-directory /srv/demo/releases/R --env-file /srv/demo/releases/R/.env -f /srv/demo/releases/R/docker-compose.yml -f /srv/demo/releases/R/.podship/override.yml',
        ),
      );
    });
  });

  test('shq quotes for a POSIX shell', () async {
    for (final s in ['plain', "it's", r'$(rm -rf /)', 'a b', '']) {
      final r = await Process.run('/bin/bash', ['-c', 'printf %s ${shq(s)}']);
      expect(r.stdout, s);
    }
  });
}
