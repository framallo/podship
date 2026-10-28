// `--plan` and `--dry-run` through the command line: they print the plan
// and change nothing. A fake ssh records every script and recorded API
// fixtures answer Cloudflare and SES; nothing reaches a server or an API.
@Tags(['unit'])
library;

import 'dart:io';

import 'package:podship/podship.dart';
import 'package:test/test.dart';

import 'app_test.dart' as app;

const config = '/Users/me/.cloudflared/config.yml';

/// A local tunnel (config.yml on the host), no Cloudflare API: the path
/// that `domain add/remove` takes without `--provider cloudflare`.
const yaml =
    '''
project: demo
environments:
  production:
    host: mac-studio
    dir: /srv/demo
    ports: {web: 8087, api: 8086}
    health: {url: "http://127.0.0.1:{port:web}/health"}
    proxy:
      kind: cloudflare_tunnel
      config: $config
      service: io.example.mac-tunnel
      tunnel_id: abc
    domains:
      - host: app.example.com
        routes: [{port: web}]
      - host: new.example.com
        routes: [{port: web}]
''';

/// The tunnel config on the host: it routes app.example.com, not
/// new.example.com, so both an add and a remove would change it.
const tunnelYaml = '''
tunnel: abc
credentials-file: /Users/me/.cloudflared/abc.json
ingress:
  - hostname: app.example.com
    service: http://localhost:8087
  - service: http_status:404
''';

/// Answers the scripts podship sends (the environment and cloudflared locks,
/// the state, the tunnel config) and records every script.
class RecordingSsh extends Ssh {
  final scripts = <String>[];

  String _answer(String script) {
    scripts.add(script);
    if (script.contains('owner.json') && script.contains('LOCKED')) {
      return 'LOCKED\n';
    }
    if (script.contains('locks/cloudflared') && script.contains('echo OK')) {
      return 'OK\n';
    }
    if (script.contains('REGISTRY-BEGIN')) {
      return 'REGISTRY-BEGIN\n\nREGISTRY-END\nPORTS \n';
    }
    if (script.contains('cat ') && script.contains(config)) return tunnelYaml;
    return '';
  }

  @override
  Future<String> capture(
    String host,
    String script, {
    List<int>? stdin,
  }) async => _answer(script);

  @override
  Future<({int exitCode, String stdout, String stderr})> captureResult(
    String host,
    String script, {
    List<int>? stdin,
  }) async => (exitCode: 0, stdout: _answer(script), stderr: '');

  @override
  Future<int> lines(
    String host,
    String script,
    void Function(String line, bool stderr) onLine,
  ) async {
    _answer(script);
    return 0;
  }
}

/// The scripts that change the tunnel: its lock, the write, the restart.
Iterable<String> writes(RecordingSsh ssh) => ssh.scripts.where(
  (s) =>
      s.contains('locks/cloudflared') ||
      s.contains('ingress validate') ||
      s.contains('mv -f') ||
      s.contains('launchctl') ||
      s.contains('systemctl'),
);

void main() {
  late Directory dir;
  late RecordingSsh ssh;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('podship-plan-');
    File('${dir.path}/podship.yaml').writeAsStringSync(yaml);
    ssh = RecordingSsh();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<int?> run(List<String> args) =>
      PodshipRunner(ssh: ssh).run(['-C', dir.path, ...args]);

  group('domain without Cloudflare', () {
    test('the fake answers like a host whose tunnel would change', () async {
      // Without --plan the remove writes and restarts: the fake sees it.
      final code = await run([
        '--yes',
        'domain',
        'remove',
        'app.example.com',
        '--env',
        'production',
      ]);
      expect(code, 0);
      expect(writes(ssh), isNotEmpty);
    });

    for (final flag in ['--plan', '--dry-run']) {
      test('remove $flag does not write the tunnel config nor restart '
          'it', () async {
        final code = await run([
          'domain',
          'remove',
          'app.example.com',
          '--env',
          'production',
          flag,
        ]);
        expect(code, 0);
        expect(writes(ssh), isEmpty);
      });

      test('add $flag does not write the tunnel config nor restart '
          'it', () async {
        final code = await run([
          'domain',
          'add',
          'new.example.com',
          '--env',
          'production',
          flag,
        ]);
        expect(code, 0);
        expect(writes(ssh), isEmpty);
      });
    }
  });

  group('every command with --plan, through Cloudflare and SES', () {
    late FixtureTransport http;
    late app.FakeSsh cfSsh;

    setUp(() {
      File('${dir.path}/podship.yaml').writeAsStringSync(app.yaml);
      http = FixtureTransport([...app.before(), ...app.writes()]);
      cfSsh = app.FakeSsh();
    });

    final commands = [
      ['dns', 'apply'],
      ['dns', 'apply', '--remove'],
      ['tunnel', 'route'],
      ['tunnel', 'unroute'],
      ['domain', 'add'],
      ['domain', 'remove'],
      ['domain', 'add', '--provider', 'cloudflare'],
      ['domain', 'remove', '--provider', 'cloudflare'],
      ['email', 'setup'],
      ['app', 'setup'],
      ['app', 'teardown'],
      ['app', 'teardown', '--email'],
    ];
    for (final c in commands) {
      test('${c.join(' ')} --plan changes nothing', () async {
        final code = await PodshipRunner(
          ssh: cfSsh,
          integrations: Integrations(
            secrets: MapSecrets({
              cloudflareTokenKey: 'cf-test-token',
              awsCredentialsKey: AwsCredentials(
                'AKIDEXAMPLE',
                'secret',
              ).toJson(),
            }),
            transport: http,
          ),
        ).run(['-C', dir.path, ...c, '--env', 'production', '--plan']);
        expect(code, 0);
        expect(http.calls, isNotEmpty, reason: 'the plan reads the API');
        expect([for (final w in http.writes) w.key], isEmpty);
        expect(
          cfSsh.scripts.where(
            (s) =>
                s.contains('owner.json') ||
                s.contains('locks/cloudflared') ||
                s.contains('mv -f'),
          ),
          isEmpty,
        );
      });
    }
  });

  test('console install --dry-run writes no project folder', () async {
    final project = '${dir.path}/console';
    try {
      await PodshipRunner(ssh: ssh).run([
        'console',
        'install',
        '--host',
        'mac-studio',
        '--hostname',
        'console.example.com',
        '--image',
        'ghcr.io/example/console:1',
        '--admin',
        'owner@example.com',
        '--project',
        project,
        '--dry-run',
      ]);
    } on Object {
      // The steps' dry runs may stop on the fake host; the folder matters.
    }
    expect(Directory(project).existsSync(), isFalse);
    expect(ssh.scripts.where((s) => s.contains('ssh-keygen')), isEmpty);
  });
}
