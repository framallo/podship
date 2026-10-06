// deploy: build, upload, switch, check health, roll back on failure.
//
// Images are built ON THE SERVER, from the uploaded files. Two reasons:
// the server's CPU architecture often differs from the developer's machine
// (arm64 laptops, x86_64 servers), and an rsync of changed source files is
// much smaller than `docker save` of full images. The server also keeps the
// Docker layer cache between deploys.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../api/events.dart';
import '../files/ignore.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../release/release.dart';
import '../remote/ssh.dart';
import 'backup_ops.dart';
import 'context.dart';
import 'resolve.dart';
import 'scripts.dart';
import 'state.dart';
import 'tests.dart';

/// The commit a release comes from.
class GitInfo {
  GitInfo(
    this.sha, {
    this.worktreeDirty = false,
    this.ref = 'HEAD',
    bool? dirty,
  }) : dirty = dirty ?? false;
  final String sha;

  /// Whether the release has uncommitted changes. Only true in worktree
  /// mode; a git export is clean whatever the working tree holds.
  final bool dirty;

  /// Whether the working tree has uncommitted changes.
  final bool worktreeDirty;

  GitInfo shipping(SourceMode mode) => GitInfo(
    sha,
    worktreeDirty: worktreeDirty,
    ref: ref,
    dirty: mode == SourceMode.worktree && worktreeDirty,
  );
  final String ref;

  /// Reads the commit of [ref] in [root]. Outside git, the sha is `nogit`.
  static Future<GitInfo> read(String root, String ref) async {
    final r = await Process.run('git', [
      'rev-parse',
      ref,
    ], workingDirectory: root);
    if (r.exitCode != 0) return GitInfo('nogit', worktreeDirty: true, ref: ref);
    final st = await Process.run('git', [
      'status',
      '--porcelain',
      '--untracked-files=no',
    ], workingDirectory: root);
    return GitInfo(
      (r.stdout as String).trim(),
      worktreeDirty: (st.stdout as String).trim().isNotEmpty,
      ref: ref,
    );
  }
}

class DeployOptions {
  const DeployOptions({
    this.source,
    this.skipWeb = false,
    this.skipBackup = false,
    this.skipHooks = false,
    this.publicCheck = true,
    this.skipTests = false,
    this.tests,
  });

  /// Overrides `build.source`.
  final SourceMode? source;
  final bool skipWeb;
  final bool skipBackup;
  final bool skipHooks;

  /// Whether the health check also fetches the public URL. Off for a first
  /// deploy, before the domain points at the new environment.
  final bool publicCheck;

  /// Skip the test stage.
  final bool skipTests;

  /// Receives the test results while the plan runs.
  final TestRun? tests;
}

/// Test results of one deploy, filled while the plan runs.
class TestRun {
  final List<SuiteResult> results = [];
  String? recordPath;
  bool get ok => results.every((r) => r.ok);
}

/// The compose files of [env], relative to the release root.
List<String> composeFilesOf(PodshipConfig config, EnvConfig env) => [
  ...config.compose.files,
  ...env.composeFiles,
];

/// Writes the `.podship/` folder of a release into [releaseRoot] (local).
void writeReleaseMeta({
  required PodshipConfig config,
  required ResolvedEnv r,
  required String releaseRoot,
  required String id,
  required GitInfo git,
  String? promotedFrom,
  Map<String, String> pinnedImages = const {},
}) {
  final env = r.env;
  final l = EnvLayout(env);
  final files = composeFilesOf(config, env);
  final texts = [
    for (final f in files)
      () {
        final file = File(p.join(releaseRoot, f));
        if (!file.existsSync()) {
          throw ConfigException('compose file $f is not in the release');
        }
        return file.readAsStringSync();
      }(),
  ];
  final built = builtServices(texts);
  final shared = env.database.mode == DatabaseMode.shared;
  final dir = Directory(p.join(releaseRoot, '.podship'))
    ..createSync(recursive: true);
  void w(String name, String text) =>
      File(p.join(dir.path, name)).writeAsStringSync(text);
  final images = pinnedImages.isNotEmpty
      ? pinnedImages.values.toList()
      : [for (final s in built) imageName(env.composeProject, s, id)];
  w(
    'override.yml',
    overrideYaml(
      composeProject: env.composeProject,
      release: id,
      built: pinnedImages.isNotEmpty ? const [] : built,
      buildContexts: env.buildContexts ?? config.compose.buildContexts,
      pinnedImages: pinnedImages,
      sharedNetwork: shared ? DatabaseConfig.sharedNetwork : null,
      serverService: env.serverService,
    ),
  );
  w('compose-files', '${files.join('\n')}\n');
  w('images', images.isEmpty ? '' : '${images.join('\n')}\n');
  w('status', 'pending\n');
  w(
    'release.json',
    '${const JsonEncoder.withIndent('  ').convert(ReleaseMeta(id: id, sha: git.sha, ref: git.ref, dirty: git.dirty, createdAt: DateTime.now().toUtc().toIso8601String(), createdBy: Platform.environment['USER'] ?? '', images: images, promotedFrom: promotedFrom).toJson())}\n',
  );
  final sh = File(p.join(dir.path, 'compose.sh'))
    ..writeAsStringSync(
      composeSh(
        composeProject: env.composeProject,
        releaseDir: l.release(id),
        composeFiles: files,
        ports: r.ports,
        remotePath: env.remotePath,
      ),
    );
  Process.runSync('chmod', ['755', sh.path]);
}

/// The remote script that turns the upload folder into release [id].
String makeReleaseScript(ResolvedEnv r, String id, {String? from}) {
  final env = r.env;
  final l = EnvLayout(env);
  final rel = l.release(id);
  final pwLink = env.secrets.passwordsLink!;
  return '''
cd ${shq(l.dir)}
mkdir -p releases
[ -e ${shq(rel)} ] && { echo "release $id already exists" >&2; exit 1; }
_cplink ${shq(from ?? l.upload)} ${shq('$rel.podship-tmp')}
mv ${shq('$rel.podship-tmp')} ${shq(rel)}
ln -sfn ${shq(l.envFile)} ${shq('$rel/.env')}
if [ -f ${shq(l.passwordsFile)} ]; then
  mkdir -p ${shq(p.posix.dirname('$rel/$pwLink'))}
  ln -sfn ${shq(l.passwordsFile)} ${shq('$rel/$pwLink')}
fi
chmod 755 ${shq('$rel/.podship/compose.sh')}
echo "release $id ready"
''';
}

/// The checks and setup before an upload.
String prepareScript(PodshipConfig config, ResolvedEnv r) {
  final env = r.env;
  final l = EnvLayout(env);
  return '''
command -v docker >/dev/null || { echo "docker is not installed on \$(hostname); run: podship server bootstrap --env ${env.name}" >&2; exit 1; }
docker compose version >/dev/null || { echo "the docker compose plugin is missing" >&2; exit 1; }
mkdir -p ${shq(l.releases)} ${shq(l.upload)}
chmod 700 ${shq(l.state)}
[ -f ${shq(l.envFile)} ] || { echo "missing ${l.envFile}: run podship secret init --env ${env.name}" >&2; exit 1; }
${installAssets(env)}''';
}

/// Plans a deploy of [git] to [r].
Plan planDeploy({
  required Ctx ctx,
  required ResolvedEnv r,
  required EnvState state,
  required GitInfo git,
  required DateTime now,
  required String snapshot,
  DeployOptions options = const DeployOptions(),
}) {
  final config = ctx.config;
  final env = r.env;
  final l = EnvLayout(env);
  final source = options.source ?? config.build.source;
  final id = ReleaseId.create(
    now,
    git.sha,
    suffix: source == SourceMode.worktree && git.worktreeDirty ? 'dirty' : null,
  ).toString();
  final root = config.root;
  final buildRoot = source == SourceMode.git ? snapshot : root;
  final old = state.current;
  final reg = state.registry..put(r.entry);

  final steps = <Step>[
    if (source == SourceMode.git)
      ActionStep(
        'Export ${git.ref} (${git.sha.substring(0, git.sha.length.clamp(0, 7))})',
        'git archive ${git.sha} → $snapshot',
        () => exportCommit(root, git.sha, snapshot),
      ),
    if (!options.skipTests &&
        config.tests.runner == TestRunner.local &&
        config.tests.forEnv(env.name).isNotEmpty)
      ActionStep(
        'Run tests (${config.tests.forEnv(env.name).map((s) => s.name).join(', ')})',
        'on this machine, in ${source == SourceMode.git ? 'the export' : 'the project'}; a failure stops the deploy',
        () => _runTests(
          ctx,
          env,
          git.sha,
          options.tests ?? TestRun(),
          () => runSuitesLocally(
            ctx,
            config.tests.forEnv(env.name),
            buildRoot,
            '$snapshot.tests',
          ),
        ),
      ),
    if (!options.skipWeb)
      for (final app in config.build.flutterWeb)
        LocalStep('Build Flutter web: ${app.name}', [
          'flutter',
          'build',
          'web',
          '--release',
          '--base-href',
          app.baseHref,
          '--output',
          p.join(buildRoot, app.output),
          ...app.args,
        ], cwd: p.join(buildRoot, app.path)),
    if (!options.skipHooks)
      for (final cmd in config.build.preDeploy)
        LocalStep('Pre-deploy hook', ['bash', '-c', cmd], cwd: buildRoot),
    ActionStep(
      'Select files and write release $id',
      'apply .gitignore, .podshipignore and build.files; write .podship/',
      () async {
        await selectInto(
          from: buildRoot,
          to: snapshot,
          rules: config.build.files,
          inPlace: source == SourceMode.git,
        );
        writeReleaseMeta(
          config: config,
          r: r,
          releaseRoot: snapshot,
          id: id,
          git: git.shipping(source),
        );
      },
    ),
    RemoteStep(
      'Prepare ${env.host}:${env.dir}',
      env.host,
      ctx.header(env) +
          prepareScript(config, r) +
          writeRegistry(env, state.registryText, reg.render()),
    ),
    UploadStep('Upload files', env.host, snapshot, l.upload),
    RemoteStep(
      'Create release $id',
      env.host,
      ctx.header(env) + makeReleaseScript(r, id),
    ),
    if (!options.skipTests &&
        config.tests.runner == TestRunner.container &&
        config.tests.forEnv(env.name).isNotEmpty)
      ActionStep(
        'Run tests in containers on ${env.host}',
        'from the release files; a failure stops the deploy before the build',
        () => _runTests(
          ctx,
          env,
          git.sha,
          options.tests ?? TestRun(),
          () => runSuitesInContainers(
            ctx,
            env,
            config.tests.forEnv(env.name),
            l.release(id),
            '$snapshot.tests',
          ),
        ),
      ),
    RemoteStep(
      'Build images on the server',
      env.host,
      ctx.header(env) +
          [
            ...(env.remotePreBuild ?? config.compose.remotePreBuild),
            '${shq(l.composeSh(id))} build',
          ].join('\n'),
    ),
    if (env.backup != null && env.backup!.beforeDeploy && !options.skipBackup)
      RemoteStep(
        'Back up the database before the switch',
        env.host,
        '${ctx.header(env)}'
            '${state.dbRunning ? '' : 'echo "no database running yet: no backup"; exit 0\n'}'
            '${backupSetup(config, r)}${backupNow(env)}',
      ),
    if (env.migrations == MigrationMode.maintenance)
      RemoteStep(
        'Apply migrations',
        env.host,
        '${ctx.header(env)}'
            '${env.database.mode == DatabaseMode.perEnv ? '${shq(l.composeSh(id))} up -d --no-build ${env.database.service}\n' : ''}'
            '${shq(l.composeSh(id))} run --rm --no-deps '
            '-e SERVERPOD_SERVER_ROLE=maintenance '
            '-e SERVERPOD_APPLY_MIGRATIONS=true ${env.serverService}\n',
      ),
  ];
  final switchIndex = steps.length;
  steps.addAll([
    RemoteStep(
      'Switch to $id',
      env.host,
      ctx.header(env) + switchTo(l, id, action: 'deploy', from: old),
    ),
    HealthStep(
      'Health check',
      env.host,
      r.healthUrls,
      publicUrls: options.publicCheck ? r.publicHealthUrls : const [],
      attempts: env.health.attempts,
      intervalSeconds: env.health.intervalSeconds,
    ),
  ]);
  final guardTo = steps.length - 1;
  final toPrune = releasesToPrune(
    [...state.ids, id],
    current: id,
    previous: old,
    keep: env.keepReleases,
  );
  steps.add(
    RemoteStep(
      'Mark $id healthy and keep ${env.keepReleases} releases',
      env.host,
      ctx.header(env) + setStatus(l, id, 'ok') + prune(l, toPrune),
    ),
  );
  if (!options.skipHooks) {
    for (final cmd in config.build.postDeploy) {
      steps.add(LocalStep('Post-deploy hook', ['bash', '-c', cmd], cwd: root));
    }
  }
  final recovery = <Step>[
    RemoteStep(
      'Mark $id failed',
      env.host,
      ctx.header(env) + setStatus(l, id, 'failed'),
    ),
    if (old != null) ...[
      RemoteStep(
        'Roll back to $old',
        env.host,
        ctx.header(env) + switchTo(l, old, action: 'auto-rollback', from: id),
      ),
      HealthStep(
        'Health check of $old',
        env.host,
        r.healthUrls,
        attempts: env.health.attempts,
        intervalSeconds: env.health.intervalSeconds,
      ),
    ],
  ];
  return Plan(
    'deploy ${config.project} to ${env.name} as $id',
    steps,
    recovery: recovery,
    guardFrom: switchIndex,
    guardTo: guardTo,
  );
}

Future<void> _runTests(
  Ctx ctx,
  EnvConfig env,
  String sha,
  TestRun run,
  Future<List<SuiteResult>> Function() body,
) async {
  final results = await body();
  run.results
    ..clear()
    ..addAll(results);
  try {
    run.recordPath = await writeTestRecord(ctx, env, sha, results);
  } catch (e) {
    ctx.log.warn('could not store the test results on ${env.host}: $e');
  }
  final failed = [
    for (final r in results)
      if (!r.ok) r,
  ];
  if (failed.isNotEmpty) {
    throw Aborted(
      'tests failed: ${failed.map((r) => '${r.suite} (${r.timedOut ? 'timed out' : '${r.failed} failed, exit code ${r.exitCode}${r.failures.isEmpty ? '' : ': ${r.failures.take(5).join('; ')}'}'}; log ${r.log})').join(', ')}',
    );
  }
}

/// Writes the backup settings file (no secrets) before a backup runs.
String backupConfInstall(PodshipConfig config, ResolvedEnv r) =>
    installAssets(r.env) +
    writeFile(
      backupConfPath(r.env),
      backupConf(config, r, encrypt: r.env.backup!.recipients.isNotEmpty),
      mode: '600',
    );

/// Exports commit [sha] of [root] into [dest] with `git archive`.
Future<void> exportCommit(String root, String sha, String dest) async {
  await Directory(dest).create(recursive: true);
  final git = await Process.start('git', [
    'archive',
    '--format=tar',
    sha,
  ], workingDirectory: root);
  final tar = await Process.start('tar', ['-x', '-C', dest]);
  final errs = git.stderr.transform(utf8.decoder).join();
  await git.stdout.pipe(tar.stdin);
  final codes = await Future.wait([git.exitCode, tar.exitCode]);
  if (codes.any((c) => c != 0)) {
    throw Exception('git archive failed: ${await errs}');
  }
}

/// Keeps only the selected files. With [inPlace], deletes the others from
/// [from] (== [to]); otherwise copies the selected files to [to].
Future<List<String>> selectInto({
  required String from,
  required String to,
  required List<String> rules,
  required bool inPlace,
}) async {
  final selected = selectFiles(from, extraRules: rules);
  if (inPlace) {
    final keep = selected.toSet();
    final all = Directory(from).listSync(recursive: true, followLinks: false);
    for (final e in all) {
      if (e is Directory) continue;
      final rel = p.relative(e.path, from: from).replaceAll(r'\', '/');
      if (!keep.contains(rel)) e.deleteSync();
    }
  } else {
    for (final rel in selected) {
      final src = p.join(from, rel), dst = p.join(to, rel);
      Directory(p.dirname(dst)).createSync(recursive: true);
      final link = Link(src);
      if (link.existsSync()) {
        Link(dst).createSync(link.targetSync());
      } else {
        File(src).copySync(dst);
      }
    }
  }
  return selected;
}
