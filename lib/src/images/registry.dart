// A registry on the podship machine. The server pulls from it through an
// ssh tunnel, so only the layers it lacks travel, and nothing is exposed
// on the network: the registry listens on this machine's loopback, the
// tunnel ends on the server's loopback, and both ends need the password.
//
//   ~/.podship/registry/htpasswd     bcrypt, read by the registry
//   ~/.podship/registry/credentials  user:password (0600), for docker login
//
// Docker accepts plain HTTP for 127.0.0.0/8 registries. Docker Desktop
// runs its daemon in a VM whose 127.0.0.1 is not the host's, so a Docker
// Desktop server cannot reach the tunnel: podship uses `load` there.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:path/path.dart' as p;

import '../remote/ssh.dart';

/// The user of the podship registry.
const registryUser = 'podship';

/// The registry container on this machine.
const registryContainer = 'podship-registry';

/// The registry login.
class RegistryAuth {
  RegistryAuth(this.user, this.password);
  final String user;
  final String password;

  /// A new random password (32 bytes, base64url).
  static RegistryAuth generate() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return RegistryAuth(
      registryUser,
      base64Url.encode(bytes).replaceAll('=', ''),
    );
  }

  /// The htpasswd line (bcrypt) that the registry checks.
  String htpasswd({int rounds = 10}) =>
      '$user:${BCrypt.hashpw(password, BCrypt.gensalt(logRounds: rounds))}';
}

/// Whether [line] (`user:$2…`) accepts [user] and [password].
bool htpasswdAccepts(String line, String user, String password) {
  final i = line.indexOf(':');
  if (i < 0 || line.substring(0, i) != user) return false;
  final hash = line.substring(i + 1).trim();
  try {
    return BCrypt.checkpw(password, hash);
  } catch (_) {
    return false;
  }
}

/// The folder of the registry files on this machine.
String registryDir() => p.join(
  Platform.environment['HOME'] ?? Directory.systemTemp.path,
  '.podship',
  'registry',
);

/// Reads the login, or creates it (and the htpasswd file) the first time.
RegistryAuth loadOrCreateAuth([String? dir]) {
  final d = dir ?? registryDir();
  final cred = File(p.join(d, 'credentials'));
  final ht = File(p.join(d, 'htpasswd'));
  if (cred.existsSync() && ht.existsSync()) {
    final t = cred.readAsStringSync().trim();
    final i = t.indexOf(':');
    if (i > 0) {
      final a = RegistryAuth(t.substring(0, i), t.substring(i + 1));
      if (htpasswdAccepts(ht.readAsStringSync().trim(), a.user, a.password)) {
        return a;
      }
    }
  }
  Directory(d).createSync(recursive: true);
  final a = RegistryAuth.generate();
  cred.writeAsStringSync('${a.user}:${a.password}\n');
  Process.runSync('chmod', ['600', cred.path]);
  ht.writeAsStringSync('${a.htpasswd()}\n');
  Process.runSync('chmod', ['644', ht.path]);
  return a;
}

/// The `docker run` arguments of the registry container.
List<String> registryRunArgs(int port, String dir) => [
  'run',
  '-d',
  '--name',
  registryContainer,
  '--restart',
  'unless-stopped',
  '-p',
  '127.0.0.1:$port:5000',
  '-v',
  'podship-registry:/var/lib/registry',
  '-v',
  '$dir:/auth:ro',
  '-e',
  'REGISTRY_AUTH=htpasswd',
  '-e',
  'REGISTRY_AUTH_HTPASSWD_REALM=podship',
  '-e',
  'REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd',
  '-e',
  'REGISTRY_STORAGE_DELETE_ENABLED=true',
  'registry:2',
];

/// The remote script that logs in through the tunnel, pulls [refs] (by
/// digest) and tags each as its release name, then logs out. The password
/// is the first line of standard input: it is never in an argument.
String pullScript(String registry, Map<String, String> refsToTags) {
  final b = StringBuffer()
    ..writeln('IFS= read -r PODSHIP_REGISTRY_PASSWORD')
    ..writeln(
      'printf "%s" "\$PODSHIP_REGISTRY_PASSWORD" | docker login ${shq(registry)} -u $registryUser --password-stdin >/dev/null',
    )
    ..writeln('unset PODSHIP_REGISTRY_PASSWORD')
    ..writeln(
      'trap ${shq('docker logout $registry >/dev/null 2>&1 || true')} EXIT',
    );
  for (final e in refsToTags.entries) {
    b
      ..writeln('docker pull -q ${shq(e.key)}')
      ..writeln('docker tag ${shq(e.key)} ${shq(e.value)}')
      ..writeln('docker image rm ${shq(e.key)} >/dev/null 2>&1 || true');
  }
  return b.toString();
}

/// Starts the registry on this machine when it does not run.
Future<void> ensureRegistry(int port, RegistryAuth auth) async {
  final st = await Process.run('docker', [
    'inspect',
    '-f',
    '{{.State.Running}}',
    registryContainer,
  ]);
  if (st.exitCode == 0 && '${st.stdout}'.trim() == 'true') return;
  if (st.exitCode == 0) {
    final r = await Process.run('docker', ['start', registryContainer]);
    if (r.exitCode == 0) return;
    await Process.run('docker', ['rm', '-f', registryContainer]);
  }
  final r = await Process.run('docker', registryRunArgs(port, registryDir()));
  if (r.exitCode != 0) {
    throw Exception('cannot start the podship registry: ${r.stderr}');
  }
  // Wait until it answers.
  for (var i = 0; i < 30; i++) {
    final c = await Process.run('curl', [
      '-s',
      '-o',
      '/dev/null',
      '-w',
      '%{http_code}',
      'http://127.0.0.1:$port/v2/',
    ]);
    if ('${c.stdout}' == '401' || '${c.stdout}' == '200') return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw Exception('the podship registry does not answer on 127.0.0.1:$port');
}

/// Logs the local Docker in to the registry.
Future<void> localLogin(int port, RegistryAuth auth) async {
  final proc = await Process.start('docker', [
    'login',
    '127.0.0.1:$port',
    '-u',
    auth.user,
    '--password-stdin',
  ]);
  proc.stdin.write(auth.password);
  await proc.stdin.close();
  final err = await proc.stderr.transform(utf8.decoder).join();
  await proc.stdout.drain<void>();
  if (await proc.exitCode != 0) {
    throw Exception('docker login 127.0.0.1:$port failed: $err');
  }
}
