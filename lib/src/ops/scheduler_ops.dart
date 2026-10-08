// scheduler: install, status, run-once, uninstall, and the jobs that
// `backup schedule` and `backup pull --schedule` write into a registry.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../plan/plan.dart';
import '../remote/ssh.dart';
import '../scheduler/agent.dart';
import '../scheduler/scheduler.dart';
import '../server/registry.dart';
import 'context.dart';
import 'resolve.dart';
import 'scripts.dart';

/// A machine that runs a scheduler: a server of an environment, or this
/// machine (for the off-site pulls).
class SchedulerTarget {
  SchedulerTarget({required this.host, required this.home, this.remotePath});

  /// The server of [env].
  factory SchedulerTarget.ofEnv(EnvConfig env) => SchedulerTarget(
    host: env.host,
    home: env.podshipHome,
    remotePath: env.remotePath,
  );

  /// This machine. Its home is `PODSHIP_HOME`, else the home of an
  /// environment with `host: local`, else `~/podship`.
  factory SchedulerTarget.local(PodshipConfig config) {
    final local = config.environments.values
        .where((e) => isLocalHost(e.host))
        .firstOrNull;
    return SchedulerTarget(
      host: localHost,
      home: localPodshipHome(localEnvHome: local?.podshipHome),
      remotePath: local?.remotePath,
    );
  }

  final String host;
  final String home;
  final String? remotePath;

  bool get isLocal => isLocalHost(host);
  String get label => isLocal ? 'this machine' : host;
  String get registryPath => '$home/registry.yaml';
  String get path => agentPath(remotePath);

  /// The header of every script on this machine.
  String header() {
    final b = StringBuffer('set -euo pipefail\n$portableHelpers');
    if (remotePath != null) {
      b.writeln('export PATH=${shq(remotePath!)}:"\$PATH"');
    }
    return b.toString();
  }

  Future<String> query(Ctx ctx, String script) =>
      ctx.ssh.capture(host, header() + script);
}

/// The backup job of [r] for the registry of its server.
ScheduledJob backupJob(Ctx ctx, ResolvedEnv r) {
  final env = r.env;
  final b = env.backup!;
  return ScheduledJob(
    kind: JobKind.backup,
    project: ctx.config.project,
    env: env.name,
    script: '${env.libDir}/backup.sh',
    conf: backupConfPath(env),
    log: '${env.podshipHome}/log/${b.unit}.log',
    path: agentPath(env.remotePath),
  );
}

/// The pull job of [env] for the registry of this machine.
ScheduledJob pullJob(Ctx ctx, EnvConfig env) => ScheduledJob(
  kind: JobKind.pull,
  project: ctx.config.project,
  env: env.name,
  projectDir: ctx.config.root,
  path: agentPath(null),
);

/// Plans `backup pull --schedule`: the pull job in this machine's registry.
Plan planPullSchedule(
  Ctx ctx,
  EnvConfig env,
  SchedulerTarget t, {
  required Registry registry,
  required String registryText,
  bool remove = false,
}) {
  final job = pullJob(ctx, env);
  if (remove) {
    registry.removeJob(job.id);
  } else {
    registry.putJob(job);
  }
  return Plan(
    '${remove ? 'remove' : 'schedule'} the off-site pull of ${env.name} on ${t.label}',
    [
      RemoteStep(
        '${remove ? 'Remove' : 'Write'} ${job.id} ${remove ? 'from' : 'into'} ${t.registryPath}',
        t.host,
        t.header() + writeRegistryAt(t, registryText, registry.render()),
      ),
    ],
  );
}

/// Replaces the registry of [t], but only if nobody changed it since
/// podship read [previous].
String writeRegistryAt(SchedulerTarget t, String previous, String next) {
  final prevB64 = base64.encode(utf8.encode(previous));
  final path = t.registryPath;
  return '''
mkdir -p ${shq(p.posix.dirname(path))}
now=\$(cat ${shq(path)} 2>/dev/null || true)
was=\$(echo ${shq(prevB64)} | base64 -d)
if [ "\$(printf '%s' "\$now" | _sha256)" != "\$(printf '%s' "\$was" | _sha256)" ]; then
  echo "the registry changed while podship was planning; run the command again" >&2
  exit 1
fi
${writeFile(path, next)}''';
}

/// Reads the registry of [t].
Future<String> readRegistryText(Ctx ctx, SchedulerTarget t) =>
    t.query(ctx, 'cat ${shq(t.registryPath)} 2>/dev/null || true\n');

/// Whether [t] runs macOS.
Future<bool> isMacos(Ctx ctx, SchedulerTarget t) async =>
    (await t.query(ctx, 'uname -s\n')).trim() == 'Darwin';

/// The status of the scheduler on [t].
Future<SchedulerStatus> schedulerStatus(Ctx ctx, SchedulerTarget t) async =>
    parseStatus(
      await t.query(ctx, statusScript(t.home)),
      host: t.host,
      home: t.home,
    );

/// The podship binary to put on a machine: `--binary`, this executable
/// when it is a compiled podship, else a `dart compile exe` of the package.
/// A compile of a clean git checkout is cached by commit under
/// `~/.cache/podship/bin`, so two installs from the same source upload the
/// same bytes and the second one is a no-op. Returns the local path.
Future<String> localBinary(Ctx ctx, {String? binary}) async {
  if (binary != null) {
    if (!File(binary).existsSync()) throw Aborted('$binary does not exist');
    return binary;
  }
  final (exe, pre) = podshipCommand();
  if (pre.isEmpty) return exe;
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:podship/podship.dart'),
  );
  if (lib == null) {
    throw Aborted(
      'cannot find the podship sources to compile the agent binary; '
      'pass --binary <a compiled podship>',
    );
  }
  final root = p.dirname(p.dirname(lib.toFilePath()));
  final rev = await _cleanRevision(root);
  final out = rev == null
      ? p.join(
          Directory.systemTemp.createTempSync('podship-bin-').path,
          'podship',
        )
      : p.join(
          Platform.environment['HOME'] ?? Directory.systemTemp.path,
          '.cache',
          'podship',
          'bin',
          'podship-$rev',
        );
  if (rev != null && File(out).existsSync()) return out;
  ctx.log.info('compiling podship for the scheduler agent');
  Directory(p.dirname(out)).createSync(recursive: true);
  final r = await Process.run('dart', [
    'compile',
    'exe',
    p.join(root, 'bin', 'podship.dart'),
    '-o',
    out,
  ]);
  if (r.exitCode != 0) throw Aborted('dart compile exe failed: ${r.stderr}');
  return out;
}

/// The commit of [root] when it is a git checkout with no local changes.
Future<String?> _cleanRevision(String root) async {
  try {
    final st = await Process.run('git', ['-C', root, 'status', '--porcelain']);
    if (st.exitCode != 0 || '${st.stdout}'.trim().isNotEmpty) return null;
    final rev = await Process.run('git', [
      '-C',
      root,
      'rev-parse',
      '--short=12',
      'HEAD',
    ]);
    final sha = '${rev.stdout}'.trim();
    return rev.exitCode == 0 && sha.isNotEmpty ? sha : null;
  } catch (_) {
    return null;
  }
}

String _sha256File(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

/// Puts [local] at `<home>/bin/podship` on [t] when it differs. Returns
/// what happened, for the log.
Future<String> installBinary(Ctx ctx, SchedulerTarget t, String local) async {
  final bin = schedulerBin(t.home);
  final arch = (await Process.run('uname', ['-sm'])).stdout.toString().trim();
  final remote = await t.query(ctx, '''
uname -sm
[ -x ${shq(bin)} ] && _sha256 ${shq(bin)} | cut -d" " -f1 || echo none
''');
  final lines = const LineSplitter().convert(remote.trim());
  final remoteArch = lines.first.trim();
  final remoteSha = lines.length > 1 ? lines[1].trim() : 'none';
  if (remoteArch != arch) {
    throw Aborted(
      '${t.label} is $remoteArch and this machine is $arch: compile podship '
      'there and pass --binary, or install podship on its PATH',
    );
  }
  if (remoteSha == _sha256File(local)) return 'unchanged';
  if (ctx.dryRun) return 'would upload';
  await t.query(ctx, 'mkdir -p ${shq(p.posix.dirname(bin))}\n');
  final res = await Process.run(t.isLocal ? 'cp' : 'scp', [
    if (!t.isLocal) ...ctx.ssh.options(),
    if (!t.isLocal) '-q',
    local,
    remoteSpec(t.host, '$bin.new'),
  ]);
  if (res.exitCode != 0) throw Aborted('upload failed: ${res.stderr}');
  final v = await t.query(ctx, '''
chmod 755 ${shq('$bin.new')}
mv -f ${shq('$bin.new')} ${shq(bin)}
${shq(bin)} --version
''');
  return 'installed ${v.trim()}';
}

/// The imported units of a machine and the jobs the registry gets.
class SchedulerInstallPlan {
  SchedulerInstallPlan({
    required this.plan,
    required this.imported,
    required this.binary,
    required this.at,
  });
  final Plan plan;
  final List<LegacyUnit> imported;
  final String binary;
  final String at;
}

/// Plans `scheduler install` on [t]: the binary, the import of the per
/// environment agents into the registry, their retirement, and the agent.
/// Idempotent: a second run with nothing changed changes nothing.
Future<SchedulerInstallPlan> planSchedulerInstall(
  Ctx ctx,
  SchedulerTarget t, {
  String? at,
  String? binary,
  List<String> replaces = const [],
}) async {
  final macos = await isMacos(ctx, t);
  final local = await localBinary(ctx, binary: binary);
  final registryText = await readRegistryText(ctx, t);
  final registry = Registry.parse(registryText);
  final legacy = parseLegacyUnits(
    await t.query(ctx, legacyScanScript),
    registry,
  );
  for (final u in legacy) {
    // A job written by `backup schedule` or `backup pull --schedule` wins
    // over the import; the legacy unit is retired either way.
    registry.jobs.putIfAbsent(u.job.id, () => u.job);
  }
  if (at != null) {
    registry.scheduler = SchedulerSettings(at: SchedulerSettings.validTime(at));
  }
  final settings = registry.scheduler;
  final next = registry.render();
  final steps = <Step>[
    ActionStep(
      'Put the podship binary at ${schedulerBin(t.home)}',
      'upload when its checksum differs',
      () async => ctx.log.info('binary: ${await installBinary(ctx, t, local)}'),
    ),
    if (next != registryText)
      RemoteStep(
        'Write the jobs and the run time into ${t.registryPath}',
        t.host,
        t.header() + writeRegistryAt(t, registryText, next),
      ),
    if (legacy.isNotEmpty || replaces.isNotEmpty)
      RemoteStep(
        'Retire the per-environment agents',
        t.host,
        t.header() +
            retireLegacyScript(legacy, replaces: replaces, macos: macos),
      ),
    RemoteStep(
      'Register $schedulerLabel (nightly at ${settings.at}, and at load)',
      t.host,
      t.header() +
          (macos
              ? installLaunchdScript(
                  home: t.home,
                  settings: settings,
                  path: t.path,
                )
              : installSystemdScript(
                  home: t.home,
                  settings: settings,
                  path: t.path,
                )),
    ),
  ];
  return SchedulerInstallPlan(
    plan: Plan('install the scheduler on ${t.label}', steps),
    imported: legacy,
    binary: local,
    at: settings.at,
  );
}

Plan planSchedulerUninstall(SchedulerTarget t, {required bool macos}) => Plan(
  'remove the scheduler agent of ${t.label} (the registry and its jobs stay)',
  [
    RemoteStep(
      'Remove ${macos ? schedulerLabel : '$schedulerUnit.timer'}',
      t.host,
      t.header() + uninstallScript(macos: macos),
    ),
  ],
);
