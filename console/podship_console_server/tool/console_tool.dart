// podship console operator tool. Run from console/podship_console_server:
//
//   dart run tool/console_tool.dart test-passwords --write config/passwords.yaml
//   dart run tool/console_tool.dart sign-in-link <email> [--dir <deploy dir>]
//   dart run tool/console_tool.dart access-token <email> [--name cli] [--days 90]
//
// sign-in-link and access-token call /internal/ inside the server container
// (`docker compose exec`), with the serviceSecret of the deploy folder's
// passwords.yaml. nginx never routes /internal/. They print the link or the
// token once; nothing is written to a log.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _defaultDir = '/Users/framallo/services/podship-console';

Future<void> main(List<String> args) async {
  if (args.isEmpty) return _usage();
  final rest = args.sublist(1);
  String? opt(String name) {
    final i = rest.indexOf('--$name');
    return i >= 0 && i + 1 < rest.length ? rest[i + 1] : null;
  }

  final positional = [
    for (var i = 0; i < rest.length; i++)
      if (!rest[i].startsWith('--') &&
          (i == 0 || !rest[i - 1].startsWith('--')))
        rest[i],
  ];
  switch (args.first) {
    case 'test-passwords':
      final out = opt('write') ?? 'config/passwords.yaml';
      File(out).writeAsStringSync(_testPasswords());
      stdout.writeln('wrote test passwords to $out');
    case 'sign-in-link':
      if (positional.isEmpty) return _usage();
      exit(
        await _internal(opt('dir') ?? _defaultDir, '/internal/sign-in-link', {
          'email': positional.first,
        }),
      );
    case 'access-token':
      if (positional.isEmpty) return _usage();
      exit(
        await _internal(opt('dir') ?? _defaultDir, '/internal/access-token', {
          'email': positional.first,
          'name': opt('name') ?? 'cli-${Platform.localHostname}',
          'days': int.tryParse(opt('days') ?? '') ?? 90,
        }),
      );
    default:
      _usage();
  }
}

void _usage() {
  stderr.writeln(
    'usage: console_tool.dart test-passwords [--write FILE] | '
    'sign-in-link EMAIL [--dir DIR] | '
    'access-token EMAIL [--name NAME] [--days N] [--dir DIR]',
  );
  exit(64);
}

String _rand(int bytes) {
  final r = Random.secure();
  return base64Encode(List.generate(bytes, (_) => r.nextInt(256)));
}

/// Throwaway values for the test run of an exported commit (it has no
/// passwords.yaml).
String _testPasswords() =>
    '''
test:
  database: "test"
  serviceSecret: "${_rand(24)}"
  integrationKey: "${_rand(32)}"
  emailSecretHashPepper: "test-pepper"
  jwtHmacSha512PrivateKey: "test-jwt-hmac-private-key-for-tests-only"
  jwtRefreshTokenHashPepper: "test-refresh-pepper"
''';

/// The value of [key] under [section] in a passwords.yaml.
String? _password(String text, String section, String key) {
  String? current;
  for (final line in const LineSplitter().convert(text)) {
    final top = RegExp(r'^([A-Za-z_]+):\s*$').firstMatch(line);
    if (top != null) {
      current = top[1];
      continue;
    }
    final kv = RegExp(r'^\s+([A-Za-z_]+):\s*(.*)$').firstMatch(line);
    if (kv != null && current == section && kv[1] == key) {
      var v = kv[2]!.trim();
      if (v.length >= 2 &&
          (v.startsWith('"') && v.endsWith('"') ||
              v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      return v;
    }
  }
  return null;
}

Future<int> _internal(
  String dir,
  String path,
  Map<String, Object?> body,
) async {
  final pw = File(
    '$dir/console/podship_console_server/config/passwords.yaml',
  );
  if (!pw.existsSync()) {
    stderr.writeln('no ${pw.path}');
    return 1;
  }
  final text = pw.readAsStringSync();
  final secret =
      _password(text, 'production', 'serviceSecret') ??
      _password(text, 'shared', 'serviceSecret');
  if (secret == null || secret.isEmpty) {
    stderr.writeln('no serviceSecret in ${pw.path}');
    return 1;
  }
  final env = Map<String, String>.of(Platform.environment);
  env['PATH'] = '/opt/homebrew/bin:/usr/local/bin:${env['PATH'] ?? ''}';
  final r = await Process.run(
    'docker',
    [
      'compose',
      '-p',
      'podship-console',
      '-f',
      '$dir/current/docker-compose.console.yml',
      'exec',
      '-T',
      'server',
      'wget',
      '-qO-',
      '--header',
      'X-Podship-Service: $secret',
      '--header',
      'Content-Type: application/json',
      '--post-data',
      jsonEncode(body),
      'http://127.0.0.1:8082$path',
    ],
    environment: env,
    workingDirectory: '$dir/current',
  );
  stdout.write(r.stdout);
  stdout.writeln();
  if (r.exitCode != 0) stderr.write(r.stderr);
  return r.exitCode;
}
