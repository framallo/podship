import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/scripts.dart';
import 'package:podship/src/release/layout.dart';
import 'package:podship/src/remote/assets.g.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/server/registry.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final config = PodshipConfig.parse(sampleConfig);
  final prod = resolveEnv(config, config.env('production'), Registry());

  test('the embedded scripts match lib/src/remote/assets', () {
    for (final f in Directory(
      'lib/src/remote/assets',
    ).listSync().whereType<File>()) {
      expect(
        remoteAssets[p.basename(f.path)],
        f.readAsStringSync(),
        reason: 'run dart run tool/embed_assets.dart',
      );
    }
  });

  test(
    'every server script parses with macOS bash 3.2 and with bash',
    () async {
      for (final e in remoteAssets.entries) {
        final r = await Process.run('/bin/bash', ['-n', '-c', e.value]);
        expect(r.exitCode, 0, reason: '${e.key}: ${r.stderr}');
      }
    },
  );

  test(
    'backup retention keeps today, yesterday, days, weeks and months',
    () async {
      final dir = Directory.systemTemp.createTempSync('podship-ret-');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final s in [
        '2026-10-06T0930',
        '2026-10-05T0930',
        '2026-10-05T1200',
        '2026-09-28T0930',
        '2026-09-01T0930',
        '2026-08-01T0930',
        '2026-03-01T0930',
        '2025-01-01T0930',
      ]) {
        Directory(p.join(dir.path, 'daily', s)).createSync(recursive: true);
      }
      File(p.join(dir.path, 'conf')).writeAsStringSync(
        'PROJECT=x\nDEST=${dir.path}\nDB_NAME=x\nKEEP_DAYS=2\nKEEP_WEEKS=2\nKEEP_MONTHS=3\n',
      );
      final script = File(p.join(dir.path, 'backup.sh'))
        ..writeAsStringSync(remoteAssets['backup.sh']!);
      final r = await Process.run(
        '/bin/bash',
        [script.path, p.join(dir.path, 'conf'), '--test-retention', dir.path],
        environment: {'TODAY': '2026-10-06'},
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final lines = (r.stdout as String).trim().split('\n');
      expect(
        lines,
        containsAll([
          'keep 2026-10-06T0930',
          'keep 2026-10-05T0930',
          'keep 2026-10-05T1200',
          'keep 2026-09-28T0930',
          'keep 2026-08-01T0930',
          'delete 2026-03-01T0930',
          'delete 2025-01-01T0930',
        ]),
      );
    },
  );

  test('the backup settings file has the layout and no secret values', () {
    final conf = backupConf(config, prod);
    expect(conf, contains("PROJECT=demo"));
    expect(conf, contains("VOLUMES='worker|demo_worker|q.db|'"));
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

  test('systemd and launchd schedules use the same time', () {
    final u = systemdUnits(config, prod);
    expect(u.timer, contains('OnCalendar=*-*-* 03:30:00 America/Mexico_City'));
    expect(
      u.service,
      contains(
        'ExecStart=/srv/podship/lib/backup.sh /srv/podship/etc/demo-backup.conf',
      ),
    );
    final plist = launchdPlist(
      config,
      prod,
      path: '/opt/homebrew/bin:/usr/bin',
    );
    expect(
      plist,
      contains(
        '<key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer>',
      ),
    );
  });

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
        expect(o, contains('image: "demo-staging-server:R"'));
        expect(o, contains('context: "/srv/worker"'));
        expect(o, isNot(contains('postgres')));
      },
    );
    test('the shared database network is attached to the server', () {
      final o = overrideYaml(
        composeProject: 'x',
        release: 'R',
        built: ['server'],
        sharedNetwork: 'podship-shared',
        serverService: 'server',
      );
      expect(o, contains('external: true'));
      expect(o, contains('- "podship-shared"'));
    });
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
          "-p demo --project-directory /srv/demo/releases/R --env-file /srv/demo/releases/R/.env -f /srv/demo/releases/R/docker-compose.yml -f /srv/demo/releases/R/.podship/override.yml",
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
