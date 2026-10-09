@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:podship/src/integrations/console_secrets.dart';
import 'package:podship/src/integrations/secrets.dart';
import 'package:podship/src/protocol/tokens.dart';
import 'package:test/test.dart';

/// A console that answers the credentials API like podship console does.
Future<HttpServer> fakeConsole({
  bool awsConnected = true,
  String expectToken = 'psc_test',
  List<String>? seen,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    seen?.add(req.uri.path);
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    req.response.headers.contentType = ContentType.json;
    if (auth != 'Bearer $expectToken') {
      req.response.statusCode = 401;
      req.response.write('{"error":"unauthorized"}');
    } else if (req.uri.path ==
        '/podship/v1/integrations/cloudflare/credentials') {
      req.response.write(
        jsonEncode({'provider': 'cloudflare', 'token': 'cf-1'}),
      );
    } else if (req.uri.path == '/podship/v1/integrations/aws/credentials' &&
        awsConnected) {
      req.response.write(
        jsonEncode({
          'provider': 'aws',
          'access_key_id': 'ASIATEST',
          'secret_access_key': 'secret',
          'session_token': 'session',
          'expiration': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      );
    } else {
      req.response.statusCode = 409;
      req.response.write('{"error":"notConnected"}');
    }
    await req.response.close();
  });
  return server;
}

void main() {
  tearDown(ConsoleCredentials.clear);

  test(
    'the console comes before the Keychain, the environment before both',
    () async {
      final server = await fakeConsole();
      addTearDown(server.close);
      final url = 'http://127.0.0.1:${server.port}';
      final got = await ConsoleCredentials.prime(url: url, token: 'psc_test');
      expect(got, {'cloudflare', 'aws'});

      final store = TokenStore(fileFallback: '/nonexistent/tokens.json');
      final secrets = SystemSecrets(store: store, environment: const {});
      expect(secrets.read(cloudflareTokenKey), 'cf-1');
      final aws = AwsCredentials.fromJson(secrets.read(awsCredentialsKey)!);
      expect(aws.accessKeyId, 'ASIATEST');
      expect(aws.sessionToken, 'session');

      final env = SystemSecrets(
        store: store,
        environment: const {'CLOUDFLARE_API_TOKEN': 'from-env'},
      );
      expect(env.read(cloudflareTokenKey), 'from-env');
    },
  );

  test(
    'a provider that is not connected gives nothing; the other still does',
    () async {
      final server = await fakeConsole(awsConnected: false);
      addTearDown(server.close);
      final got = await ConsoleCredentials.prime(
        url: 'http://127.0.0.1:${server.port}',
        token: 'psc_test',
      );
      expect(got, {'cloudflare'});
      expect(ConsoleCredentials.read(awsCredentialsKey), isNull);
    },
  );

  test('a refused token gives nothing and warns without the token', () async {
    final server = await fakeConsole();
    addTearDown(server.close);
    final warnings = <String>[];
    final got = await ConsoleCredentials.prime(
      url: 'http://127.0.0.1:${server.port}',
      token: 'psc_wrong',
      warn: warnings.add,
    );
    expect(got, isEmpty);
    expect(warnings, isNotEmpty);
    expect(warnings.join(), isNot(contains('psc_wrong')));
  });

  test('only the providers asked for are fetched', () async {
    final seen = <String>[];
    final server = await fakeConsole(seen: seen);
    addTearDown(server.close);
    await ConsoleCredentials.prime(
      url: 'http://127.0.0.1:${server.port}',
      token: 'psc_test',
      providers: const {'cloudflare'},
    );
    expect(seen, ['/podship/v1/integrations/cloudflare/credentials']);
  });

  test(
    'console url: environment, then ~/.podship/config.yaml, then podship.yaml',
    () {
      final home = Directory.systemTemp.createTempSync('ps-home');
      final cwd = Directory.systemTemp.createTempSync('ps-cwd');
      addTearDown(() {
        home.deleteSync(recursive: true);
        cwd.deleteSync(recursive: true);
      });
      expect(
        ConsoleCredentials.consoleUrl(
          environment: const {},
          home: home.path,
          cwd: cwd.path,
        ),
        isNull,
      );
      File('${cwd.path}/podship.yaml').writeAsStringSync(
        'project: x\nconsole:\n  url: https://project.example\n',
      );
      expect(
        ConsoleCredentials.consoleUrl(
          environment: const {},
          home: home.path,
          cwd: cwd.path,
        ),
        'https://project.example',
      );
      Directory('${home.path}/.podship').createSync();
      File(
        '${home.path}/.podship/config.yaml',
      ).writeAsStringSync('console:\n  url: https://global.example\n');
      expect(
        ConsoleCredentials.consoleUrl(
          environment: const {},
          home: home.path,
          cwd: cwd.path,
        ),
        'https://global.example',
      );
      expect(
        ConsoleCredentials.consoleUrl(
          environment: const {'PODSHIP_CONSOLE_URL': 'https://env.example'},
          home: home.path,
          cwd: cwd.path,
        ),
        'https://env.example',
      );
    },
  );
}
