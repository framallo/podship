// deploy: build, upload, switch, check health, roll back on failure.
//
// Images are built on THIS machine when it can (build.location: local or
// local-docker, see ../images/): the server binary is compiled here
// (cross-compiled when the server's CPU differs), put in a slim runtime
// image, and shipped to the server, which only runs it. The tests, the
// image build and the pre-deploy backup run at the same time; the switch
// waits for all three. build.location: remote keeps the old way: the
// server builds from the uploaded files.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../api/events.dart';
import '../files/ignore.dart';
import '../images/images.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../release/release.dart';
import '../server/registry.dart';
import '../remote/ssh.dart';
import 'backup_ops.dart';
import 'bluegreen.dart';
import 'context.dart';
import 'inputs.dart';
import 'resolve.dart';
import 'scheduler_ops.dart' show agentStep;
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
    this.fullTests = false,
    this.tests,
    this.inputs,
    this.images,
  });

  /// Where the images are built and how they reach the server (see
  /// [computeImagePlan]). Null: the server builds them.
  final ImagePlan? images;

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

  /// Run every suite, even one whose inputs passed before.
  final bool fullTests;

  /// Receives the test results while the plan runs.
  final TestRun? tests;

  /// What may be reused or skipped (see [computeDeployInputs]).
  final DeployInputs? inputs;
}

/// What a deploy knows about its inputs before it plans: the hash of each
/// Flutter web app and of each test suite, the earlier release whose build
/// an app can take, and the suites that passed before with the same hash.
class DeployInputs {
  DeployInputs({
    this.webHashes = const {},
    this.webReuse = const {},
    this.suites,
  });

  /// App name → input hash (apps without a hash are always built).
  final Map<String, String> webHashes;

  /// App name → the release on the server whose build has the same hash.
  final Map<String, String> webReuse;

  /// The test suites' hashes and prior passes.
  final SuitePlan? suites;

  bool reuses(FlutterWebApp app) => webReuse.containsKey(app.name);
}

/// Computes [DeployInputs] for a deploy of [git] to [env], from the commit
/// (never from the working tree) and the releases on the server.
Future<DeployInputs> computeDeployInputs({
  required Ctx ctx,
  required EnvConfig env,
  required GitInfo git,
  required EnvState state,
  required SourceMode source,
  bool fullTests = false,
  bool skipWeb = false,
}) async {
  final config = ctx.config;
  final root = config.root;
  if (source != SourceMode.git || git.sha == 'nogit') return DeployInputs();
  final webHashes = <String, String>{};
  final webReuse = <String, String>{};
  if (!skipWeb && config.build.flutterWeb.isNotEmpty) {
    final flutter = await flutterVersionTag();
    for (final app in config.build.flutterWeb) {
      final paths = await packageInputs(
        root,
        git.sha,
        app.path,
        extra: app.inputs,
      );
      final h = await inputsHash(
        root,
        git.sha,
        paths,
        salt: [
          'base_href=${app.baseHref}',
          'args=${app.args.join(' ')}',
          'output=${app.output}',
          ?flutter,
        ],
      );
      if (h == null) continue;
      webHashes[app.name] = h;
      if (!app.reuse) continue;
      // The newest healthy release with the same build, current first.
      final candidates = [
        ...state.releases.where((r) => r.id == state.current),
        ...state.releases.reversed.where((r) => r.id != state.current),
      ];
      for (final r in candidates) {
        if (r.status == 'ok' && r.meta?.web[app.name] == h) {
          webReuse[app.name] = r.id;
          break;
        }
      }
    }
  }
  // The toolchain is part of a suite's inputs: a Dart or Flutter upgrade
  // that leaves the lock alone must still run the tests.
  final tools = [
    ?await dartVersionTag(),
    if (config.build.flutterWeb.isNotEmpty) ?await flutterVersionTag(),
  ];
  final suiteHashes = <String, String>{};
  for (final suite in config.tests.forEnv(env.name)) {
    final paths = await packageInputs(
      root,
      git.sha,
      suite.dir,
      extra: suite.inputs,
    );
    final h = await inputsHash(
      root,
      git.sha,
      paths,
      salt: [
        'command=${suite.command}',
        'runner=${config.tests.runner.name}',
        'image=${suite.image ?? ''}',
        ...tools,
      ],
    );
    if (h != null) suiteHashes[suite.name] = h;
  }
  final skippable = {
    for (final suite in config.tests.forEnv(env.name))
      if (suite.skipUnchanged && suiteHashes.containsKey(suite.name))
        suite.name: suiteHashes[suite.name]!,
  };
  final prior = fullTests
      ? <String, PriorPass>{}
      : await findPriorPasses(ctx, skippable);
  return DeployInputs(
    webHashes: webHashes,
    webReuse: webReuse,
    suites: SuitePlan(hashes: suiteHashes, prior: prior),
  );
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
  Map<String, String> web = const {},
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
  final sp = env.serverpod;
  final serverPorts = servicePorts(texts, env.serverService);
  final defining = [
    for (final (i, t) in texts.indexed)
      if (allServices([t]).contains(env.serverService)) files[i],
  ];
  final extras = OverrideExtras(
    serverEnv: {...sp.environment, ...?env.email?.environment},
    stopGraceSeconds: sp.stopGraceSeconds,
    replicas: sp.replicas,
    redis: sp.needsRedis,
    serverPorts: serverPorts,
    extendsFile: defining.isEmpty
        ? null
        : p.posix.join(l.release(id), defining.first),
    replicaEntrypoint: sp.replicaEntrypoint,
    egressProxy: env.egress?.proxy,
    egressServices: env.egress?.appliesTo ?? const [],
    noProxy: env.egress?.noProxy ?? const [],
  );
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
      extras: extras,
    ),
  );
  if (sp.replicas > 1) {
    w(
      'lb.conf',
      lbConfig([
        for (final port in serverPorts) ?containerPort(port),
      ], server: env.serverService),
    );
  }
  w('compose-files', '${files.join('\n')}\n');
  w('images', images.isEmpty ? '' : '${images.join('\n')}\n');
  w('status', 'pending\n');
  w(
    'release.json',
    '${const JsonEncoder.withIndent('  ').convert(ReleaseMeta(id: id, sha: git.sha, ref: git.ref, dirty: git.dirty, createdAt: DateTime.now().toUtc().toIso8601String(), createdBy: Platform.environment['USER'] ?? '', images: images, promotedFrom: promotedFrom, web: web).toJson())}\n',
  );
  final sh = File(p.join(dir.path, 'compose.sh'))
    ..writeAsStringSync(
      composeSh(
        composeProject: env.composeProject,
        releaseDir: l.release(id),
        composeFiles: files,
        ports: r.ports,
        remotePath: env.remotePath,
        blueGreenState: blueGreenBlocker(env) == null ? l.state : null,
      ),
    );
  Process.runSync('chmod', ['755', sh.path]);
}

/// The remote script that turns the upload folder into release [id].
/// [reuse] maps a path inside the release (a Flutter web build) to the
/// release that already holds it: the files are hard-linked from there.
String makeReleaseScript(
  ResolvedEnv r,
  String id, {
  String? from,
  Map<String, String> reuse = const {},
}) {
  final env = r.env;
  final l = EnvLayout(env);
  final rel = l.release(id);
  final pwLink = env.secrets.passwordsLink!;
  final reused = StringBuffer();
  for (final e in reuse.entries) {
    final src = shq('${l.release(e.value)}/${e.key}');
    final dst = shq('$rel.podship-tmp/${e.key}');
    reused.writeln(
      '[ -d $src ] || { echo "release ${e.value} has no ${e.key} to reuse" >&2; exit 1; }',
    );
    reused.writeln(
      'mkdir -p ${shq(p.posix.dirname('$rel.podship-tmp/${e.key}'))}',
    );
    reused.writeln('rm -rf $dst');
    reused.writeln('_cplink $src $dst');
    reused.writeln('echo "reused ${e.key} from release ${e.value}"');
  }
  return '''
cd ${shq(l.dir)}
mkdir -p releases
[ -e ${shq(rel)} ] && { echo "release $id already exists" >&2; exit 1; }
_cplink ${shq(from ?? l.upload)} ${shq('$rel.podship-tmp')}
${reused}mv ${shq('$rel.podship-tmp')} ${shq(rel)}
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
''';
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
  // `scheduled:` commands, in the current release; a removed one goes.
  final project = ctx.config.project;
  for (final id in [
    for (final j in reg.jobs.values)
      if (j.kind == JobKind.command &&
          j.project == project &&
          j.env == env.name)
        j.id,
  ]) {
    reg.removeJob(id);
  }
  for (final c in env.scheduled) {
    reg.putJob(
      ScheduledJob(
        kind: JobKind.command,
        project: project,
        env: env.name,
        name: c.name,
        run: c.run,
        cwd: p.posix.normalize(p.posix.join(env.dir, 'current', c.cwd)),
        path: c.path ?? env.remotePath,
        note: 'from podship.yaml scheduled:',
      ),
    );
  }
  final inputs = options.inputs ?? DeployInputs();
  final reuse = {
    if (!options.skipWeb)
      for (final app in config.build.flutterWeb)
        if (inputs.reuses(app)) app.output: inputs.webReuse[app.name]!,
  };

  final images = options.images;
  final local = images != null && images.buildsLocally;
  // The server image carries the web builds: they are built in the image
  // lane, from the cache on this machine when unchanged.
  final webInImage = local && images.local.containsKey(env.serverService);
  final remoteServices = local ? images.remote.keys.toList() : const <String>[];
  final suites = config.tests.forEnv(env.name);
  final testStep =
      !options.skipTests &&
          config.tests.runner == TestRunner.local &&
          suites.isNotEmpty
      ? ActionStep(
          'Run tests (${suites.map((s) => s.name).join(', ')})',
          'on this machine, in ${source == SourceMode.git ? 'the export' : 'the project'}; a failure stops the deploy',
          () => _runTests(
            ctx,
            env,
            git.sha,
            options.tests ?? TestRun(),
            () => runSuitesLocally(
              ctx,
              suites,
              buildRoot,
              '$snapshot.tests',
              parallel: config.tests.parallel,
              plan: inputs.suites,
            ),
          ),
        )
      : null;
  final backupStep =
      env.backup != null && env.backup!.beforeDeploy && !options.skipBackup
      ? RemoteStep(
          'Back up the database before the switch',
          env.host,
          '${ctx.header(env)}'
              '${state.dbRunning ? '' : 'echo "no database running yet: no backup"; exit 0\n'}'
              '${backupSetup(config, r)}${backupNow(env)}',
        )
      : null;
  final imgRoot = '$snapshot.image';
  final steps = <Step>[
    if (source == SourceMode.git)
      ActionStep(
        'Export ${git.ref} (${git.sha.substring(0, git.sha.length.clamp(0, 7))})',
        'git archive ${git.sha} → $snapshot',
        () => exportCommit(root, git.sha, snapshot),
      ),
    if (local) ...[
      ActionStep(
        'Build location: ${images.decision.name}',
        images.decision.reason,
        () async {
          ctx.log.info(images.decision.reason);
          ctx.log.info('images reach ${env.host} by: ${images.shipReason}');
          for (final e in images.remote.entries) {
            ctx.log.info('${e.key} builds on the server: ${e.value}');
          }
          if (images.jitRefused != null) ctx.log.warn(images.jitRefused!);
        },
      ),
      ParallelStep('Tests, images and backup', [
        if (testStep != null) Lane('tests', [testStep]),
        Lane(
          'images',
          imageLane(
            ctx: ctx,
            env: env,
            plan: images,
            release: id,
            imgRoot: imgRoot,
            webHashes: inputs.webHashes,
            skipWeb: options.skipWeb,
            sha: source == SourceMode.git ? git.sha : null,
            runGate: !options.skipTests,
            export: () async {
              if (source == SourceMode.git) {
                await exportCommit(root, git.sha, imgRoot);
              } else {
                await selectInto(
                  from: root,
                  to: imgRoot,
                  rules: config.build.files,
                  inPlace: false,
                );
              }
            },
          ),
        ),
        if (backupStep != null)
          Lane('backup', [agentStep(ctx, env), backupStep]),
      ]),
    ] else
      ?testStep,
    if (!options.skipWeb && !webInImage)
      for (final app in config.build.flutterWeb)
        if (inputs.reuses(app))
          ActionStep(
            'Reuse Flutter web: ${app.name}',
            'same sources as release ${inputs.webReuse[app.name]}: its build is linked on the server',
            () async => ctx.log.info(
              'web ${app.name}: unchanged since release ${inputs.webReuse[app.name]}, not built',
            ),
          )
        else
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
          web: options.skipWeb || webInImage ? const {} : inputs.webHashes,
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
      ctx.header(env) +
          makeReleaseScript(r, id, reuse: webInImage ? const {} : reuse),
    ),
    if (!options.skipTests &&
        config.tests.runner == TestRunner.container &&
        suites.isNotEmpty)
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
            suites,
            l.release(id),
            '$snapshot.tests',
            parallel: config.tests.parallel,
            plan: inputs.suites,
          ),
        ),
      ),
    if (!local)
      RemoteStep(
        'Build images on the server',
        env.host,
        ctx.header(env) +
            [
              if (images != null) 'echo ${shq(images.decision.reason)}',
              ...(env.remotePreBuild ?? config.compose.remotePreBuild),
              '${shq(l.composeSh(id))} build',
            ].join('\n'),
      )
    else if (remoteServices.isNotEmpty)
      RemoteStep(
        'Build ${remoteServices.join(', ')} on the server',
        env.host,
        ctx.header(env) +
            [
              ...(env.remotePreBuild ?? config.compose.remotePreBuild),
              '${shq(l.composeSh(id))} build ${remoteServices.map(shq).join(' ')}',
            ].join('\n'),
      ),
    if (!local && backupStep != null) ...[agentStep(ctx, env), backupStep],
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
  final bgBlock = blueGreenBlocker(env);
  final bg = bgBlock == null
      ? blueGreenSteps(ctx, r, id, old: old, action: 'deploy')
      : null;
  if (env.switchMode == SwitchMode.blueGreen && bgBlock != null) {
    steps.add(
      ActionStep(
        'Switch mode: in place',
        bgBlock,
        () async => ctx.log.warn(bgBlock),
      ),
    );
  }
  final switchIndex = steps.length;
  steps.addAll([
    if (bg != null)
      bg.start
    else
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
    if (r.readinessUrl != null)
      HealthStep(
        'Serverpod readiness (/readyz)',
        env.host,
        [r.readinessUrl!],
        attempts: env.health.attempts,
        intervalSeconds: env.health.intervalSeconds,
      ),
    if (options.publicCheck && env.health.publicChecks.isNotEmpty)
      PublicChecksStep(
        'Public checks',
        [for (final c in env.health.publicChecks) c.withUrl(r.sub(c.url))],
        attempts: env.health.attempts,
        intervalSeconds: env.health.intervalSeconds,
      ),
  ]);
  final postSwitch = env.remotePostSwitch ?? config.compose.remotePostSwitch;
  if (postSwitch.isNotEmpty && !options.skipHooks) {
    steps.add(
      RemoteStep(
        'Run the post-switch commands in $id',
        env.host,
        '${ctx.header(env)}cd ${shq(l.release(id))}\n${postSwitch.join('\n')}',
      ),
    );
  }
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
  if (bg != null) steps.add(bg.stopOld);
  if (env.build.prune && !isLocalHost(env.host) && images != null) {
    final kept = [
      for (final x in [...state.ids, id])
        if (!toPrune.contains(x)) x,
    ];
    steps.add(
      ActionStep(
        'Server hygiene on ${env.host}',
        'remove images no kept release uses${local && remoteServices.isEmpty ? ', the Dart SDK images and the build cache' : ''}; report the disk saved',
        () async {
          try {
            await serverHygiene(
              ctx,
              env,
              services: images.local.keys.isEmpty
                  ? images.remote.keys.toList()
                  : [...images.local.keys, ...images.remote.keys],
              keepReleases: kept,
              buildCache: local && remoteServices.isEmpty,
            );
          } catch (e) {
            ctx.log.warn('server hygiene: $e');
          }
        },
      ),
    );
  }
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
    if (bg != null)
      ...bg.recovery
    else if (old != null) ...[
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
String backupConfInstall(PodshipConfig config, ResolvedEnv r) => writeFile(
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
