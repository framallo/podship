// scheduler: install, status, run-once, uninstall, and the jobs that
// `backup schedule` and `backup pull --schedule` write into a registry.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cli/self_commands.dart' show sourceDirOfThisProcess;
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
      RegistryWriteStep(
        '${remove ? 'Remove' : 'Write'} ${job.id} ${remove ? 'from' : 'into'} ${t.registryPath}',
        t.host,
        t.registryPath,
        header: t.header(),
        base: registryText,
        mine: registry.render(),
      ),
    ],
  );
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

/// The Dart target (`x64`, `arm64`) of a Linux `uname -sm`, or null.
String? linuxTarget(String unameSm) {
  final parts = unameSm.trim().split(RegExp(r'\s+'));
  if (parts.length != 2 || parts[0] != 'Linux') return null;
  return switch (parts[1]) {
    'x86_64' || 'amd64' => 'x64',
    'aarch64' || 'arm64' => 'arm64',
    _ => null,
  };
}

/// The podship sources of this process (for a compile), or null.
Future<String?> podshipSourceDir() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:podship/podship.dart'),
  );
  if (lib != null && lib.scheme == 'file') {
    return p.dirname(p.dirname(lib.toFilePath()));
  }
  return sourceDirOfThisProcess();
}

/// A hash of the sources that make the binary: `bin/`, `lib/` and
/// `pubspec.lock`. Two compiles of the same sources give the same key.
String sourceHash(String root) {
  final files = <String>[
    for (final d in ['bin', 'lib'])
      if (Directory(p.join(root, d)).existsSync())
        for (final e in Directory(
          p.join(root, d),
        ).listSync(recursive: true, followLinks: false))
          if (e is File && e.path.endsWith('.dart')) e.path,
    if (File(p.join(root, 'pubspec.lock')).existsSync())
      p.join(root, 'pubspec.lock'),
  ]..sort();
  final list = StringBuffer();
  for (final f in files) {
    list.writeln(
      '${sha256.convert(File(f).readAsBytesSync())} ${p.relative(f, from: root)}',
    );
  }
  return sha256
      .convert(utf8.encode(list.toString()))
      .toString()
      .substring(0, 16);
}

/// The podship binary to put on a machine that runs [targetUname]
/// (`uname -sm`): `--binary`, this executable when it is a compiled
/// podship for the same OS and CPU, else a `dart compile exe` of the
/// sources (cross-compiled for a Linux server). Compiles are cached by a
/// hash of the sources under `~/.cache/podship/bin`, so two installs from
/// the same sources upload the same bytes and the second one is a no-op.
Future<String> localBinary(
  Ctx ctx, {
  String? binary,
  String? targetUname,
}) async {
  if (binary != null) {
    if (!File(binary).existsSync()) throw Aborted('$binary does not exist');
    return binary;
  }
  final here = (await Process.run('uname', ['-sm'])).stdout.toString().trim();
  final same = targetUname == null || targetUname.trim() == here;
  final cross = same ? null : linuxTarget(targetUname);
  if (!same && cross == null) {
    throw Aborted(
      'the server is $targetUname and this machine is $here: compile podship '
      'for that OS and CPU (dart compile exe on such a machine) and pass '
      '--binary <file>',
    );
  }
  final (exe, pre) = podshipCommand();
  if (same && pre.isEmpty) return exe;
  final root = await podshipSourceDir();
  if (root == null) {
    throw Aborted(
      'cannot find the podship sources to compile the agent binary; '
      'pass --binary <a compiled podship>',
    );
  }
  final out = p.join(
    Platform.environment['HOME'] ?? Directory.systemTemp.path,
    '.cache',
    'podship',
    'bin',
    'podship-${sourceHash(root)}${cross == null ? '' : '-linux-$cross'}',
  );
  if (File(out).existsSync()) return out;
  ctx.log.info(
    'compiling podship for the server${cross == null ? '' : ' (linux-$cross)'}',
  );
  Directory(p.dirname(out)).createSync(recursive: true);
  final r = await Process.run('dart', [
    'compile',
    'exe',
    if (cross != null) ...['--target-os', 'linux', '--target-arch', cross],
    p.join(root, 'bin', 'podship.dart'),
    '-o',
    '$out.tmp',
  ], workingDirectory: root);
  if (r.exitCode != 0) throw Aborted('dart compile exe failed: ${r.stderr}');
  File('$out.tmp').renameSync(out);
  return out;
}

String _sha256File(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

/// `uname -sm` of [t].
Future<String> remoteUname(Ctx ctx, SchedulerTarget t) async =>
    (await t.query(ctx, 'uname -sm\n')).trim();

/// Puts [local] at `<home>/bin/podship` on [t] when it differs. Returns
/// what happened, for the log.
Future<String> installBinary(Ctx ctx, SchedulerTarget t, String local) async {
  final bin = schedulerBin(t.home);
  final remoteSha = (await t.query(
    ctx,
    '[ -x ${shq(bin)} ] && _sha256 ${shq(bin)} | cut -d" " -f1 || echo none\n',
  )).trim();
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

/// Makes sure the server of [env] has this podship at `<home>/bin/podship`:
/// the backup, drill and restore steps run there as `podship agent …`.
/// Removes the bash scripts older podships put in `<home>/lib`.
Future<void> ensureAgent(Ctx ctx, EnvConfig env, {String? binary}) async {
  final t = SchedulerTarget.ofEnv(env);
  final local = await localBinary(
    ctx,
    binary: binary,
    targetUname: await remoteUname(ctx, t),
  );
  final what = await installBinary(ctx, t, local);
  if (what != 'unchanged') ctx.log.info('podship on ${t.label}: $what');
  if (!ctx.dryRun) {
    await t.query(
      ctx,
      'rm -f ${shq('${env.libDir}/backup.sh')} ${shq('${env.libDir}/restore.sh')}\n',
    );
  }
}

/// The plan step that runs [ensureAgent].
Step agentStep(Ctx ctx, EnvConfig env) => ActionStep(
  'Put podship at ${schedulerBin(env.podshipHome)} on ${env.host}',
  'upload when its checksum differs',
  () => ensureAgent(ctx, env),
);

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
  final local = await localBinary(
    ctx,
    binary: binary,
    targetUname: await remoteUname(ctx, t),
  );
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
  final watchInterval = registry.watch.targets.isEmpty
      ? null
      : registry.watch.interval;
  final next = registry.render();
  final steps = <Step>[
    ActionStep(
      'Put the podship binary at ${schedulerBin(t.home)}',
      'upload when its checksum differs',
      () async => ctx.log.info('binary: ${await installBinary(ctx, t, local)}'),
    ),
    if (next != registryText)
      RegistryWriteStep(
        'Write the jobs and the run time into ${t.registryPath}',
        t.host,
        t.registryPath,
        header: t.header(),
        base: registryText,
        mine: next,
      ),
    if (legacy.isNotEmpty || replaces.isNotEmpty)
      RemoteStep(
        'Retire the per-environment agents',
        t.host,
        t.header() +
            retireLegacyScript(legacy, replaces: replaces, macos: macos),
      ),
    RemoteStep(
      'Register $schedulerLabel (nightly at ${settings.at}, and at load'
      '${watchInterval == null ? '' : '; watch every $watchInterval s'})',
      t.host,
      t.header() +
          (macos
              ? installLaunchdScript(
                  home: t.home,
                  settings: settings,
                  path: t.path,
                  watchInterval: watchInterval,
                )
              : installSystemdScript(
                  home: t.home,
                  settings: settings,
                  path: t.path,
                  watchInterval: watchInterval,
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
