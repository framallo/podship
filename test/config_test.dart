import 'package:podship/src/config/config.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('PodshipConfig.parse', () {
    test('reads a full config', () {
      final c = PodshipConfig.parse(sampleConfig);
      expect(c.project, 'demo');
      expect(c.build.source, SourceMode.git);
      expect(c.build.flutterWeb.single.baseHref, '/app/');
      expect(c.compose.buildContexts, {'worker': '/srv/worker'});
      final p = c.env('production');
      expect(p.composeProject, 'demo');
      expect(p.ports, {'web': 8087, 'api': 8086});
      expect(p.backup!.unit, 'demo-backup');
      expect(p.backup!.volumes.single.sqlite, ['q.db']);
      expect(p.backup!.recipients.single, startsWith('ssh-ed25519'));
      expect(p.proxy.kind, ProxyKind.cloudflareTunnel);
      expect(p.domains.single.routes.first.port, 'api');
      expect(p.secrets.passwordsLink, 'demo_server/config/passwords.yaml');
      expect(p.isProduction, isTrue);
    });

    test('gives defaults to other environments', () {
      final s = PodshipConfig.parse(sampleConfig).env('staging');
      expect(s.composeProject, 'demo-staging');
      expect(s.ports, {'web': 0, 'api': 0});
      expect(s.backup!.unit, 'podship-backup-demo-staging');
      expect(s.backup!.dir, '/srv/backups/demo-staging');
      expect(s.backup!.schedule, '');
      expect(s.backup!.layout.plain, 'plain');
      expect(s.migrations, MigrationMode.onStart);
      expect(s.keepReleases, 5);
      expect(s.podshipHome, '/srv/podship');
      expect(s.registryPath, '/srv/podship/registry.yaml');
    });

    test('rejects an unknown environment name', () {
      expect(
        () => PodshipConfig.parse(sampleConfig).env('qa'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('requires the host and an absolute dir', () {
      expect(
        () => PodshipConfig.parse('project: x\nenvironments:\n  a:\n    dir: /x\n    health: {url: u}\n'),
        throwsA(isA<ConfigException>().having((e) => e.message, 'message', contains('host'))),
      );
      expect(
        () => PodshipConfig.parse('project: x\nenvironments:\n  a:\n    host: h\n    dir: x\n    health: {url: u}\n'),
        throwsA(isA<ConfigException>().having((e) => e.message, 'message', contains('absolute'))),
      );
    });

    String twoEnvs(String a, String b) => '''
project: x
environments:
  production:
    host: h
    health: {url: u}
$a
  staging:
    host: h
    health: {url: u}
$b
''';

    test('refuses two environments on one host that share a port', () {
      expect(
        () => PodshipConfig.parse(twoEnvs(
          '    dir: /a\n    ports: {web: 9000}',
          '    dir: /b\n    ports: {web: 9000}',
        )),
        throwsA(isA<ConfigException>().having((e) => e.message, 'm', contains('port 9000'))),
      );
    });

    test('refuses a shared directory or compose project', () {
      expect(
        () => PodshipConfig.parse(twoEnvs('    dir: /a', '    dir: /a')),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => PodshipConfig.parse(twoEnvs(
          '    dir: /a\n    compose_project: same',
          '    dir: /b\n    compose_project: same',
        )),
        throwsA(isA<ConfigException>()),
      );
    });

    test('allows the same ports on different hosts', () {
      final c = PodshipConfig.parse('''
project: x
environments:
  production: {host: a, dir: /a, ports: {web: 9000}, health: {url: u}}
  staging: {host: b, dir: /a, ports: {web: 9000}, health: {url: u}}
''');
      expect(c.environments, hasLength(2));
    });

    test('refuses one domain in two environments', () {
      expect(
        () => PodshipConfig.parse('''
project: x
environments:
  production: {host: a, dir: /a, health: {url: u}, domains: [{host: d.com, routes: [{port: 1}]}]}
  staging: {host: b, dir: /b, health: {url: u}, domains: [{host: d.com, routes: [{port: 2}]}]}
'''),
        throwsA(isA<ConfigException>().having((e) => e.message, 'm', contains('d.com'))),
      );
    });

    test('validates enums', () {
      expect(
        () => PodshipConfig.parse('project: x\nbuild: {source: zip}\nenvironments:\n  a: {host: h, dir: /a, health: {url: u}}\n'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => PodshipConfig.parse('project: x\nenvironments:\n  a: {host: h, dir: /a, health: {url: u}, migrations: later}\n'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('shared database mode names the database after the compose project', () {
      final c = PodshipConfig.parse(
        'project: shop\nenvironments:\n  staging: {host: h, dir: /a, health: {url: u}, database: {mode: shared}}\n',
      );
      final d = c.env('staging').database;
      expect(d.mode, DatabaseMode.shared);
      expect(d.name, 'shop_staging');
      expect(d.user, 'shop_staging');
    });
  });
}
