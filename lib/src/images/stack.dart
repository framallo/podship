// A release image in a throwaway stack: its own Docker network, its
// services (Postgres) and the server, then health. Used by the release
// gate on this machine (with a test-runner container) and by
// `podship images check` on a server (start, /health, stop).
//
// Everything carries the label `podship.stack=<id>`, so a stack is removed
// even after a crash: `docker rm -f $(docker ps -aq --filter label=…)`.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../remote/ssh.dart';
import '../ops/context.dart';
import 'target.dart';

/// The script that starts the stack [id]: network, services, server. It
/// waits until each service is ready and the server answers [StackServer]
/// health inside its container. [publish] maps the server port to
/// `127.0.0.1:<publish>` on the host.
String stackUpScript({
  required String id,
  required String serverImage,
  required StackServer server,
  required List<StackService> services,
  int? publish,
  int waitSeconds = 120,
}) {
  final net = 'podship-$id';
  final label = '--label podship.stack=$id';
  final b = StringBuffer()
    ..writeln('docker network create $label $net >/dev/null');
  for (final s in services) {
    b.writeln(
      'docker run -d $label --name $net-${s.name} --network $net '
      '--network-alias ${s.name} '
      '${s.env.entries.map((e) => '-e ${shq('${e.key}=${e.value}')}').join(' ')} '
      '${shq(s.image)} >/dev/null',
    );
    if (s.ready != null) {
      b
        ..writeln('ok=; for i in \$(seq $waitSeconds); do')
        ..writeln(
          '  if docker exec $net-${s.name} sh -c ${shq(s.ready!)} >/dev/null 2>&1; then ok=1; break; fi; sleep 1',
        )
        ..writeln('done')
        ..writeln(
          '[ -n "\$ok" ] || { echo "${s.name} is not ready" >&2; docker logs --tail 30 $net-${s.name} >&2; exit 1; }',
        )
        ..writeln('echo "${s.name} ready"');
    }
  }
  final ep = server.entrypoint;
  b.writeln(
    'docker run -d $label --name $net-server --network $net --network-alias server '
    '${publish == null ? '' : '-p 127.0.0.1:$publish:${server.port} '}'
    '${server.env.entries.map((e) => '-e ${shq('${e.key}=${e.value}')}').join(' ')} '
    '${ep.isEmpty ? '' : '--entrypoint ${shq(ep.first)} '}'
    '${shq(serverImage)} ${ep.skip(1).map(shq).join(' ')} >/dev/null',
  );
  final url = 'http://127.0.0.1:${server.port}${server.health}';
  b
    ..writeln('ok=; for i in \$(seq $waitSeconds); do')
    ..writeln(
      '  if docker exec $net-server wget -qO- ${shq(url)} >/dev/null 2>&1; then ok=1; break; fi',
    )
    ..writeln(
      '  [ "\$(docker inspect -f {{.State.Running}} $net-server)" = true ] || break; sleep 1',
    )
    ..writeln('done')
    ..writeln(
      '[ -n "\$ok" ] || { echo "the server did not answer $url" >&2; docker logs --tail 60 $net-server >&2; exit 1; }',
    )
    ..writeln('echo "server healthy: ${server.health} after \$i s"');
  return b.toString();
}

/// Removes every container and the network of stack [id].
String stackDownScript(String id) =>
    'ids=\$(docker ps -aq --filter label=podship.stack=$id)\n'
    '[ -z "\$ids" ] || docker rm -f \$ids >/dev/null\n'
    'docker network rm podship-$id >/dev/null 2>&1 || true\n';

/// The default services of a check: Postgres with a throwaway password,
/// named like the compose database service, with the env's database name.
({List<StackService> services, Map<String, String> env}) defaultStack(
  EnvConfig env, {
  Iterable<String> passwordKeys = const [],
}) {
  final pw = 'check-${DateTime.now().microsecondsSinceEpoch}';
  final r = Random.secure();
  String secret() =>
      base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256)));
  return (
    services: [
      StackService(
        name: env.database.service,
        image: 'postgres:16-alpine',
        env: {
          'POSTGRES_USER': env.database.user,
          'POSTGRES_DB': env.database.name,
          'POSTGRES_PASSWORD': pw,
        },
        ready: 'pg_isready -U ${env.database.user} -d ${env.database.name}',
      ),
    ],
    env: {
      // Throwaway values for the other Serverpod passwords the server
      // reads at startup (secrets.password_keys of any environment).
      for (final k in passwordKeys)
        if (k != 'database') 'SERVERPOD_PASSWORD_$k': secret(),
      'SERVERPOD_PASSWORD_database': pw,
    },
  );
}

/// Runs [script] on this machine.
Future<int> runLocalScript(Ctx ctx, String script) => runLines('bash', [
  '-c',
  'set -euo pipefail\n$script',
], (l, err) => ctx.log.output(l, stderr: err));

/// The Chrome for Testing version of the runner image on amd64.
const defaultChromeForTesting = '141.0.7390.122';

/// The Dockerfile of the gate's test runner: Flutter, a browser and its
/// driver, pinned. On amd64, Chrome for Testing and its chromedriver; on
/// arm64 (no Chrome for Testing build), Debian's Chromium and
/// chromium-driver, which match each other.
String runnerDockerfile({
  required String flutter,
  required String arch,
  String chrome = defaultChromeForTesting,
}) {
  final b = StringBuffer()
    ..writeln('# Written by podship: the release gate test runner.')
    ..writeln('FROM debian:bookworm-slim')
    ..writeln(
      'RUN apt-get update && apt-get install -y --no-install-recommends '
      'ca-certificates curl git unzip xz-utils zip procps fonts-liberation '
      'fonts-noto-color-emoji \\',
    );
  if (arch == 'amd64') {
    b
      ..writeln('  && rm -rf /var/lib/apt/lists/*')
      ..writeln(
        'RUN curl -fsSL -o /tmp/c.zip https://storage.googleapis.com/chrome-for-testing-public/$chrome/linux64/chrome-linux64.zip \\',
      )
      ..writeln(
        '  && curl -fsSL -o /tmp/d.zip https://storage.googleapis.com/chrome-for-testing-public/$chrome/linux64/chromedriver-linux64.zip \\',
      )
      ..writeln(
        '  && unzip -q /tmp/c.zip -d /opt && unzip -q /tmp/d.zip -d /opt \\',
      )
      ..writeln('  && apt-get update \\')
      ..writeln(
        '  && apt-get install -y --no-install-recommends \$(cat /opt/chrome-linux64/deb.deps | tr "\\n" " ") \\',
      )
      ..writeln(
        '  && ln -s /opt/chrome-linux64/chrome /usr/local/bin/chrome \\',
      )
      ..writeln(
        '  && ln -s /opt/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver \\',
      )
      ..writeln('  && rm -rf /tmp/*.zip /var/lib/apt/lists/*')
      ..writeln('ENV CHROME_EXECUTABLE=/usr/local/bin/chrome');
  } else {
    b
      ..writeln('  chromium chromium-driver \\')
      ..writeln('  && rm -rf /var/lib/apt/lists/*')
      ..writeln('ENV CHROME_EXECUTABLE=/usr/bin/chromium');
  }
  b
    ..writeln(
      'RUN git clone -q --depth 1 --branch $flutter https://github.com/flutter/flutter.git /opt/flutter',
    )
    ..writeln(
      'ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/root/.pub-cache/bin:\$PATH \\',
    )
    ..writeln('    FLUTTER_SUPPRESS_ANALYTICS=true CI=true')
    ..writeln(
      'RUN flutter config --no-analytics --enable-web >/dev/null && flutter precache --web && dart --disable-analytics',
    )
    ..writeln('WORKDIR /work');
  return b.toString();
}

/// The runner image tag for these versions.
String runnerTag(String flutter, String arch, String chrome) =>
    'podship-gate-runner:flutter-$flutter-${arch == 'amd64' ? 'cft-$chrome' : 'chromium'}-$arch';

/// This machine's Flutter version, like `3.38.1`.
Future<String?> hostFlutterVersion() async {
  try {
    final r = await Process.run('flutter', ['--version', '--machine']);
    if (r.exitCode != 0) return null;
    final s = '${r.stdout}';
    final j = jsonDecode(s.substring(s.indexOf('{'))) as Map<String, Object?>;
    return j['frameworkVersion'] as String?;
  } catch (_) {
    return null;
  }
}

/// Builds the runner image once (it is cached by its tag). Returns the tag.
Future<String> ensureRunnerImage(
  Ctx ctx,
  ImageGateConfig gate,
  DockerPlatform local,
) async {
  if (gate.image != null) return gate.image!;
  final flutter = gate.flutter ?? await hostFlutterVersion();
  if (flutter == null) {
    throw Aborted(
      'tests.gate.image: set flutter (no flutter on this machine to copy the version from)',
    );
  }
  final chrome = gate.chrome ?? defaultChromeForTesting;
  final tag = runnerTag(flutter, local.arch, chrome);
  final have = await Process.run('docker', ['image', 'inspect', tag]);
  if (have.exitCode == 0) return tag;
  ctx.log.info('building the gate runner $tag (once; cached)');
  final dir = await Directory.systemTemp.createTemp('podship-runner-');
  try {
    File(p.join(dir.path, 'Dockerfile')).writeAsStringSync(
      runnerDockerfile(flutter: flutter, arch: local.arch, chrome: chrome),
    );
    final code = await runLines('docker', [
      'buildx',
      'build',
      '--load',
      '--platform',
      '$local',
      '-t',
      tag,
      dir.path,
    ], (l, err) => ctx.log.output(l, stderr: err));
    if (code != 0) throw Aborted('building the gate runner failed');
  } finally {
    await dir.delete(recursive: true);
  }
  return tag;
}

/// The `docker run` arguments of the runner: in the stack's network, the
/// commit export at /work (it must be under a folder the Docker VM shares,
/// like the home folder), a pub cache volume, chromedriver on 4444, then
/// the seed and the command.
List<String> runnerArgs({
  required String id,
  required String image,
  required String workDir,
  required ImageGateConfig gate,
}) {
  final script = [
    'chromedriver --port=4444 >/tmp/chromedriver.log 2>&1 &',
    if (gate.seed != null && gate.seedIn == 'runner') gate.seed!,
    gate.command,
  ].join('\n');
  return [
    'run',
    '--rm',
    '--label',
    'podship.stack=$id',
    '--name',
    'podship-$id-runner',
    '--network',
    'podship-$id',
    '--shm-size',
    '1g',
    '-v',
    '$workDir:/work',
    '-v',
    'podship-gate-pub-cache:/root/.pub-cache',
    '-w',
    p.posix.normalize(p.posix.join('/work', gate.dir)),
    '-e',
    'PODSHIP_GATE_SERVER=http://server:${gate.server.port}',
    for (final e in gate.env.entries) ...['-e', '${e.key}=${e.value}'],
    image,
    'bash',
    '-c',
    'set -e\n$script',
  ];
}

/// Where the artifacts of [release] go on this machine.
String artifactsDir(String project, String env, String release) => p.join(
  Platform.environment['HOME'] ?? Directory.systemTemp.path,
  '.podship',
  'artifacts',
  project,
  env,
  release,
);
