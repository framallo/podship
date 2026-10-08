// Images built on the podship machine and shipped to the server.
//
// [computeImagePlan] decides, before the deploy plan exists, where each
// built service is built and how the server gets it. [imageLane] gives the
// steps that run on this machine (next to the tests and the backup), and
// [serverHygiene] cleans the server after a healthy deploy.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../ops/context.dart';
import '../ops/inputs.dart';
import 'archive.dart';
import 'dockerfile.dart';
import 'registry.dart';
import 'stack.dart';
import 'target.dart';

/// Sizes and times of one deploy's images, for the log and the history.
class ImageReport {
  String? location;
  String? reason;
  String? ship;
  String? shipReason;
  String? platform;
  final Map<String, int> sizes = {};
  final Map<String, String> remoteServices = {};
  int shippedBytes = 0;
  int totalBytes = 0;
  int layersSkipped = 0;
  bool fullFallback = false;
  String? gate;
  String? gateArtifacts;
  final Map<String, int> millis = {};

  Map<String, Object?> toJson() => {
    'location': ?location,
    'reason': ?reason,
    'ship': ?ship,
    'ship_reason': ?shipReason,
    'platform': ?platform,
    if (sizes.isNotEmpty) 'sizes': sizes,
    if (remoteServices.isNotEmpty) 'remote_services': remoteServices,
    if (totalBytes > 0) ...{
      'shipped_bytes': shippedBytes,
      'archive_bytes': totalBytes,
      'layers_skipped': layersSkipped,
    },
    if (fullFallback) 'full_fallback': true,
    'gate': ?gate,
    'gate_artifacts': ?gateArtifacts,
    if (millis.isNotEmpty) 'ms': millis,
  };
}

/// What a deploy does with images.
class ImagePlan {
  ImagePlan({
    required this.decision,
    this.ship = 'none',
    this.shipReason = '',
    this.local = const {},
    this.remote = const {},
    this.runtime,
    this.server,
    this.jit = false,
    this.jitRefused,
    this.mainTarget = 'bin/main.dart',
    this.serverKey,
    ImageReport? report,
  }) : report = report ?? ImageReport();

  final BuildDecision decision;

  /// `none` (the server is this machine), `load`, `registry` or `ghcr`.
  final String ship;
  final String shipReason;

  /// Services built on this machine.
  final Map<String, ServiceBuild> local;

  /// Services the server builds, with the reason.
  final Map<String, String> remote;

  /// The runtime Dockerfile of the server service, when it is compiled
  /// here (`local`); null means Docker builds it from its own Dockerfile.
  final RuntimeDockerfile? runtime;
  final ServerDocker? server;

  /// Whether the server is compiled to kernel (JIT).
  final bool jit;

  /// Why JIT was asked but not used.
  final String? jitRefused;

  /// The entry point of the server, from the Dockerfile.
  final String mainTarget;

  /// A hash of the server image's inputs except the web builds (git mode
  /// only); with the web hashes it names a reusable server image.
  final String? serverKey;
  final ImageReport report;

  bool get buildsLocally => decision.local && local.isNotEmpty;
}

/// Reads [path] from commit [sha] in [root], or from the working tree when
/// [sha] is null.
Future<String?> readSource(String root, String? sha, String path) async {
  if (sha == null) {
    final f = File(p.join(root, path));
    return f.existsSync() ? f.readAsStringSync() : null;
  }
  final r = await Process.run('git', [
    'show',
    '$sha:$path',
  ], workingDirectory: root);
  return r.exitCode == 0 ? '${r.stdout}' : null;
}

/// Packages in [packageConfig] (a `package_config.json`) with build hooks:
/// their native libraries come from the hooks, which a kernel (JIT) file
/// does not run.
List<String> nativeAssetPackages(String packageConfig) {
  final f = File(packageConfig);
  if (!f.existsSync()) return const [];
  final j = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
  final out = <String>[];
  for (final pkg in (j['packages'] as List? ?? const [])) {
    final m = pkg as Map<String, Object?>;
    final uri = Uri.parse('${m['rootUri']}');
    final dir = uri.isAbsolute
        ? uri.toFilePath()
        : p.normalize(p.join(p.dirname(f.path), uri.toFilePath()));
    if (File(p.join(dir, 'hook', 'build.dart')).existsSync()) {
      out.add('${m['name']}');
    }
  }
  return out;
}

/// Decides where the images of a deploy of [sha] to [env] are built.
Future<ImagePlan> computeImagePlan({
  required Ctx ctx,
  required EnvConfig env,
  required String? sha,
  HostTools? host,
  ServerDocker? server,
}) async {
  final config = ctx.config;
  final b = env.build;
  if (b.location == BuildLocation.remote) {
    final pl =
        DockerPlatform.parse(b.platform ?? '') ??
        const DockerPlatform('linux', 'amd64');
    final plan = ImagePlan(
      decision: decideBuild(
        requested: BuildLocation.remote,
        host: HostTools(os: '', arch: ''),
        platform: pl,
      ),
    );
    plan.report
      ..location = 'remote'
      ..reason = plan.decision.reason;
    return plan;
  }
  server ??= await probeServer(ctx, env);
  host ??= await probeHost();
  final platform = DockerPlatform.parse(b.platform ?? '') ?? server.platform;
  final decision = decideBuild(
    requested: b.location,
    host: host,
    platform: platform,
  );
  final report = ImageReport()
    ..location = decision.name
    ..reason = decision.reason
    ..platform = '$platform';
  if (!decision.local) {
    return ImagePlan(decision: decision, server: server, report: report);
  }
  final texts = <String>[];
  for (final f in [...config.compose.files, ...env.composeFiles]) {
    final t = await readSource(config.root, sha, f);
    if (t == null) throw Aborted('$f is not in the release');
    texts.add(t);
  }
  final builds = serviceBuilds(texts);
  final serverContexts = env.buildContexts ?? config.compose.buildContexts;
  final local = <String, ServiceBuild>{};
  final remote = <String, String>{};
  for (final s in builtServices(texts)) {
    final sb = builds[s];
    if (sb == null) continue;
    if (serverContexts.containsKey(s) && !b.contexts.containsKey(s)) {
      remote[s] =
          'its build context ${serverContexts[s]} is on the server; set '
          'environments.${env.name}.build.contexts.$s to build it here';
      continue;
    }
    local[s] = sb;
  }
  RuntimeDockerfile? runtime;
  var mainTarget = 'bin/main.dart';
  var jit = b.mode == CompileMode.jit;
  String? jitRefused;
  final serverBuild = local[env.serverService];
  if (serverBuild != null && decision.location == BuildLocation.local) {
    final df = await readSource(config.root, sha, serverBuild.dockerfilePath);
    if (df == null) {
      throw Aborted('${serverBuild.dockerfilePath} is not in the release');
    }
    final t = RegExp(
      r'dart\s+(?:build\s+cli|compile\s+exe)\b[^\n]*?(?:--target[ =])?(bin/\S+\.dart)',
    ).firstMatch(df);
    if (t != null) mainTarget = t[1]!;
    if (jit) {
      final natives = nativeAssetPackages(
        p.join(config.root, '.dart_tool', 'package_config.json'),
      );
      final pkgNatives = nativeAssetPackages(
        p.join(
          config.root,
          config.serverPackage,
          '.dart_tool',
          'package_config.json',
        ),
      );
      final all = {...natives, ...pkgNatives}.toList()..sort();
      if (all.isNotEmpty) {
        jit = false;
        jitRefused =
            'build.mode jit: packages with native code (${all.join(', ')}) '
            'need their hooks, which only `dart build cli` runs; AOT instead';
      }
    }
    try {
      runtime = runtimeDockerfile(
        df,
        bundleDir: '.podship-image/bundle',
        jitKernel: jit,
      );
      if (runtime.hasRun && host.dockerPlatform != platform) {
        ctx.log.info(
          'the runtime stage of ${serverBuild.dockerfilePath} has RUN steps: '
          'they run emulated for $platform',
        );
      }
    } on DockerfileException catch (e) {
      ctx.log.warn(
        '${serverBuild.dockerfilePath}: $e. Docker on this machine builds '
        'the server image instead (local-docker).',
      );
    }
  }
  String? serverKey;
  if (sha != null && runtime != null && serverBuild != null) {
    final paths = await packageInputs(config.root, sha, config.serverPackage);
    serverKey = await inputsHash(
      config.root,
      sha,
      [...paths, serverBuild.dockerfilePath],
      salt: [
        'platform=$platform',
        'jit=$jit',
        runtime.text,
        ?await dartVersionTag(),
      ],
    );
  }
  String ship;
  String shipReason;
  if (isLocalHost(env.host)) {
    ship = 'none';
    shipReason = 'the server is this machine: the images are already there';
  } else {
    switch (b.ship) {
      case ShipMethod.auto || ShipMethod.load:
        ship = 'load';
        shipReason = server.containerdStore
            ? 'docker save → only the layers the server lacks → docker load'
            : 'docker save → docker load (the server has no containerd '
                  'image store: every layer travels)';
      case ShipMethod.registry:
        if (server.dockerDesktop) {
          ship = 'load';
          shipReason =
              'registry asked, but ${env.host} runs Docker Desktop: its '
              'daemon cannot reach the ssh tunnel; docker save/load instead';
        } else {
          ship = 'registry';
          shipReason =
              'the podship registry on this machine, pulled through an ssh tunnel';
        }
      case ShipMethod.ghcr:
        ship = 'ghcr';
        shipReason = 'push to ${b.ghcr}, the server pulls';
    }
  }
  report
    ..ship = ship
    ..shipReason = shipReason
    ..remoteServices.addAll(remote);
  return ImagePlan(
    decision: decision,
    ship: ship,
    shipReason: shipReason,
    local: local,
    remote: remote,
    runtime: runtime,
    server: server,
    jit: jit,
    jitRefused: jitRefused,
    mainTarget: mainTarget,
    serverKey: serverKey,
    report: report,
  );
}

/// Runs the release gate: a fresh export under ~/.podship/work (Docker
/// VMs share the home folder), the stack, the seed, the runner; artifacts
/// to `~/.podship/artifacts/<project>/<env>/<release>`. Always removes the
/// stack.
Future<void> runImageGate(
  Ctx ctx, {
  required EnvConfig env,
  required ImageGateConfig gate,
  required String serverImage,
  required String release,
  required String? sha,
  required ImageReport report,
}) async {
  final config = ctx.config;
  final host = await probeHost();
  final local = host.dockerPlatform ?? const DockerPlatform('linux', 'arm64');
  final runner = await ensureRunnerImage(ctx, gate, local);
  final id = 'gate-${release.replaceAll(RegExp(r'[^a-z0-9-]'), '-')}';
  final work = p.join(cacheDir(), '..', 'work', '${config.project}-$release');
  final workDir = p.normalize(work);
  if (Directory(workDir).existsSync()) {
    Directory(workDir).deleteSync(recursive: true);
  }
  Directory(workDir).createSync(recursive: true);
  try {
    if (sha != null) {
      final git = await Process.start('git', [
        'archive',
        '--format=tar',
        sha,
      ], workingDirectory: config.root);
      final tar = await Process.start('tar', ['-x', '-C', workDir]);
      await git.stdout.pipe(tar.stdin);
      if ((await git.exitCode) != 0 || (await tar.exitCode) != 0) {
        throw Aborted('gate: git archive $sha failed');
      }
    } else {
      final r = await Process.run('cp', ['-R', '${config.root}/.', workDir]);
      if (r.exitCode != 0) throw Aborted('gate: copy failed: ${r.stderr}');
    }
    await runLocalScript(ctx, stackDownScript(id));
    // Without services of its own, the gate gets the check's stack:
    // Postgres with throwaway passwords.
    final def = defaultStack(
      env,
      passwordKeys: {
        for (final x in config.environments.values) ...x.secrets.passwordKeys,
      },
    );
    final own = gate.services.isNotEmpty;
    final up = await runLocalScript(
      ctx,
      stackUpScript(
        id: id,
        serverImage: serverImage,
        server: own ? gate.server : gate.server.withEnv(def.env),
        services: own ? gate.services : def.services,
      ),
    );
    if (up != 0) throw Aborted('gate: the release image did not start');
    if (gate.seed != null && gate.seedIn == 'server') {
      final code = await runLines('docker', [
        'exec',
        'podship-$id-server',
        'sh',
        '-c',
        gate.seed!,
      ], (l, err) => ctx.log.output(l, stderr: err));
      if (code != 0) throw Aborted('gate: the seed failed (exit code $code)');
    }
    final code =
        await runLines(
          'docker',
          runnerArgs(id: id, image: runner, workDir: workDir, gate: gate),
          (l, err) => ctx.log.output(l, stderr: err),
        ).timeout(
          Duration(seconds: gate.timeoutSeconds),
          onTimeout: () async {
            await Process.run('docker', ['rm', '-f', 'podship-$id-runner']);
            return 124;
          },
        );
    final out = artifactsDir(config.project, env.name, release);
    for (final a in gate.artifacts) {
      final src = p.join(workDir, gate.dir, a);
      if (!FileSystemEntity.isDirectorySync(src) && !File(src).existsSync()) {
        continue;
      }
      Directory(out).createSync(recursive: true);
      await Process.run('cp', ['-R', src, out]);
    }
    if (Directory(out).existsSync()) {
      ctx.log.info('gate artifacts: $out');
      report.gateArtifacts = out;
    }
    if (code != 0) {
      final logs = await Process.run('docker', [
        'logs',
        '--tail',
        '40',
        'podship-$id-server',
      ]);
      ctx.log.output('${logs.stdout}${logs.stderr}', stderr: true);
      throw Aborted(
        code == 124
            ? 'gate: timed out after ${gate.timeoutSeconds} s'
            : 'gate: ${gate.command} failed (exit code $code)',
      );
    }
    report.gate = 'passed';
  } catch (_) {
    report.gate = 'failed';
    rethrow;
  } finally {
    await runLocalScript(ctx, stackDownScript(id));
    if (Directory(workDir).existsSync()) {
      Directory(workDir).deleteSync(recursive: true);
    }
  }
}

/// The local folder of a build context given in `build.contexts`.
String localContextDir(String project, String service, LocalContext c) {
  if (c.path != null) {
    final home = Platform.environment['HOME'] ?? '';
    return c.path!.startsWith('~/')
        ? p.join(home, c.path!.substring(2))
        : c.path!;
  }
  return p.join(cacheDir(), 'src', project, service);
}

/// `~/.podship/cache`.
String cacheDir() => p.join(
  Platform.environment['HOME'] ?? Directory.systemTemp.path,
  '.podship',
  'cache',
);

Future<void> _run(
  Ctx ctx,
  String exe,
  List<String> args, {
  String? cwd,
  String? what,
}) async {
  final code = await runLines(
    exe,
    args,
    (l, err) => ctx.log.output(l, stderr: err),
    workingDirectory: cwd,
  );
  if (code != 0) {
    throw Aborted(
      '${what ?? '$exe ${args.take(3).join(' ')}'}: exit code $code',
    );
  }
}

/// The steps that build (and ship) the images on this machine. [imgRoot] is
/// a private export of the commit: tests run elsewhere, so the two never
/// share `.dart_tool` or `build/`.
List<Step> imageLane({
  required Ctx ctx,
  required EnvConfig env,
  required ImagePlan plan,
  required String release,
  required String imgRoot,
  required Future<void> Function() export,
  Map<String, String> webHashes = const {},
  bool skipWeb = false,
  String? sha,
  bool runGate = true,
}) {
  final config = ctx.config;
  final report = plan.report;
  final platform = plan.decision.platform;
  final web = <Step>[], compile = <Step>[], others = <Lane>[];
  final serverImage = <Step>[];
  // A server image with the same inputs (sources, lock, Dockerfile, web
  // builds, platform, toolchain) is tagged again instead of rebuilt.
  final key = plan.serverKey == null || plan.runtime == null
      ? null
      : sha256
            .convert(
              utf8.encode(
                '${plan.serverKey}|${(webHashes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join(',')}',
              ),
            )
            .toString()
            .substring(0, 24);
  final keyFile = key == null
      ? null
      : File(
          p.join(
            cacheDir(),
            'images',
            config.project,
            '${env.composeProject}-${env.serverService}',
            key,
          ),
        );
  var reuse = false;
  Future<void> timed(String key, Future<void> Function() f) async {
    final w = Stopwatch()..start();
    try {
      await f();
    } finally {
      report.millis[key] = w.elapsedMilliseconds;
    }
  }

  if (!skipWeb && plan.local.containsKey(env.serverService)) {
    for (final app in config.build.flutterWeb) {
      final hash = webHashes[app.name];
      web.add(
        ActionStep(
          'Flutter web: ${app.name}',
          'from the cache on this machine when the inputs did not change; else flutter build web',
          () => timed('web_${app.name}', () async {
            if (reuse) return;
            final out = p.join(imgRoot, app.output);
            // A fresh export has no build/ folder; some generators (l10n
            // untranslated-messages-file) expect one.
            Directory(
              p.join(imgRoot, app.path, 'build'),
            ).createSync(recursive: true);
            final cached = hash == null
                ? null
                : p.join(cacheDir(), 'web', config.project, app.name, hash);
            if (cached != null && Directory(cached).existsSync()) {
              await _copyTree(cached, out);
              ctx.log.info(
                'web ${app.name}: unchanged (cache $hash), not built',
              );
              return;
            }
            await _run(
              ctx,
              'flutter',
              [
                'build',
                'web',
                '--release',
                '--base-href',
                app.baseHref,
                '--output',
                out,
                ...app.args,
              ],
              cwd: p.join(imgRoot, app.path),
              what: 'flutter build web',
            );
            if (cached != null) {
              await _copyTree(out, cached);
              _keepNewest(p.dirname(cached), 3);
            }
          }),
        ),
      );
    }
  }
  final rt = plan.runtime;
  if (rt != null) {
    final pkg = p.join(imgRoot, config.serverPackage);
    final bundle = p.join(imgRoot, '.podship-image', 'bundle');
    compile.add(
      ActionStep(
        plan.jit
            ? 'Compile the server to kernel (JIT)'
            : 'Compile the server for $platform',
        plan.jit
            ? 'dart compile kernel ${plan.mainTarget}'
            : 'dart build cli --target ${plan.mainTarget} --target-os linux --target-arch ${platform.dartArch}',
        () => timed('compile', () async {
          if (reuse) return;
          final out = p.join(imgRoot, '.podship-image', 'out');
          Directory(bundle).createSync(recursive: true);
          if (plan.jit) {
            final bin = p.join(bundle, 'bin');
            Directory(bin).createSync(recursive: true);
            final exeName = p.basename(
              rt.renames.values.firstOrNull ?? 'bin/main',
            );
            await _run(
              ctx,
              'dart',
              [
                'compile',
                'kernel',
                '--no-embed-sources',
                plan.mainTarget,
                '-o',
                p.join(bin, '$exeName.dill'),
              ],
              cwd: pkg,
              what: 'dart compile kernel',
            );
            final sh = File(p.join(bin, exeName))
              ..writeAsStringSync(
                '#!/bin/sh\nexec /usr/lib/dart/bin/dart "\$(dirname "\$0")/$exeName.dill" "\$@"\n',
              );
            await Process.run('chmod', ['755', sh.path]);
          } else {
            await _run(
              ctx,
              'dart',
              [
                'build',
                'cli',
                '--target',
                plan.mainTarget,
                '--target-os',
                'linux',
                '--target-arch',
                platform.dartArch,
                '--output',
                out,
              ],
              cwd: pkg,
              what: 'dart build cli',
            );
            if (Directory(bundle).existsSync()) {
              Directory(bundle).deleteSync(recursive: true);
            }
            Directory(p.join(out, 'bundle')).renameSync(bundle);
            for (final e in rt.renames.entries) {
              final from = File(p.join(bundle, e.key));
              if (from.existsSync()) from.renameSync(p.join(bundle, e.value));
            }
          }
          File(
            p.join(imgRoot, '.podship-image', 'Dockerfile'),
          ).writeAsStringSync(rt.text);
        }),
      ),
    );
  }
  for (final e in plan.local.entries) {
    final s = e.value;
    final name = imageName(env.composeProject, e.key, release);
    final svcPlatform = s.platform ?? '$platform';
    final useRuntime = e.key == env.serverService && rt != null;
    final lc = env.build.contexts[e.key];
    final ctxDir = useRuntime
        ? imgRoot
        : lc != null
        ? localContextDir(config.project, e.key, lc)
        : p.isAbsolute(s.context)
        ? s.context
        : p.join(imgRoot, s.context);
    final dockerfile = useRuntime
        ? p.join(imgRoot, '.podship-image', 'Dockerfile')
        : p.join(ctxDir, s.dockerfile ?? 'Dockerfile');
    final step = (ActionStep(
      'Build image ${e.key} for $svcPlatform',
      'docker buildx build --platform $svcPlatform -t $name'
          '${useRuntime ? ' (runtime stage only: the server was compiled here)' : ''}',
      () => timed('image_${e.key}', () async {
        if (useRuntime && reuse) {
          final id = keyFile!.readAsStringSync().trim();
          await _run(ctx, 'docker', ['tag', id, name]);
          ctx.log.info('image ${e.key}: unchanged inputs, tagged $id again');
          return;
        }
        if (lc?.git != null) await _syncGitContext(ctx, ctxDir, lc!);
        await _run(ctx, 'docker', [
          'buildx',
          'build',
          '--platform',
          svcPlatform,
          '--provenance=false',
          '--load',
          '-t',
          name,
          '-f',
          dockerfile,
          for (final a in s.args.entries) ...[
            '--build-arg',
            '${a.key}=${a.value}',
          ],
          if (s.target != null && !useRuntime) ...['--target', s.target!],
          ctxDir,
        ], what: 'docker buildx build ${e.key}');
        final size = await Process.run('docker', [
          'image',
          'inspect',
          '--format',
          '{{.Size}}',
          name,
        ]);
        final n = int.tryParse('${size.stdout}'.trim());
        if (n != null) {
          report.sizes[e.key] = n;
          ctx.log.info('image ${e.key}: ${mb(n)}');
        }
        if (useRuntime && keyFile != null) {
          final id = await Process.run('docker', [
            'image',
            'inspect',
            '--format',
            '{{.Id}}',
            name,
          ]);
          keyFile.parent.createSync(recursive: true);
          keyFile.writeAsStringSync('${id.stdout}'.trim());
          _keepNewest(keyFile.parent.path, 5, files: true);
        }
      }),
    ));
    if (useRuntime) {
      serverImage.add(step);
    } else {
      others.add(Lane(e.key, [step]));
    }
  }
  final steps = <Step>[
    ActionStep(
      'Export for the image build',
      'a second export of the commit in $imgRoot',
      () async {
        await export();
        if (keyFile != null && keyFile.existsSync()) {
          final id = keyFile.readAsStringSync().trim();
          final r = await Process.run('docker', ['image', 'inspect', id]);
          reuse = r.exitCode == 0;
          if (reuse) {
            ctx.log.info(
              'server image: same inputs as $id; no web build, no compile',
            );
          }
        }
      },
    ),
  ];
  final lanes = [
    if (web.isNotEmpty) Lane('web', web),
    if (compile.isNotEmpty) Lane('compile', compile),
    ...others,
  ];
  if (lanes.length > 1) {
    steps.add(
      ParallelStep('Build ${lanes.map((l) => l.name).join(', ')}', lanes),
    );
  } else {
    for (final l in lanes) {
      steps.addAll(l.steps);
    }
  }
  steps.addAll(serverImage);
  final gate = config.tests.imageGate;
  if (gate != null &&
      runGate &&
      gate.runsFor(env.name) &&
      plan.local.containsKey(env.serverService)) {
    steps.add(
      ActionStep(
        'Release gate (in containers)',
        'the image with ${gate.services.map((s) => s.name).join(', ')} on this machine; '
            '${gate.command} in the test runner; the image ships only when it passes',
        () => timed('gate', () async {
          await runImageGate(
            ctx,
            env: env,
            gate: gate,
            serverImage: imageName(
              env.composeProject,
              env.serverService,
              release,
            ),
            release: release,
            sha: sha,
            report: report,
          );
        }),
      ),
    );
  }
  final images = [
    for (final s in plan.local.keys) imageName(env.composeProject, s, release),
  ];
  if (images.isNotEmpty && plan.ship != 'none') {
    steps.add(
      ActionStep(
        'Ship images to ${env.host} (${plan.ship})',
        plan.shipReason,
        () => timed('ship', () async {
          switch (plan.ship) {
            case 'registry':
              await shipByRegistry(ctx, env, images, report);
            case 'ghcr':
              await shipByGhcr(ctx, env, images, report);
            default:
              await shipByLoad(ctx, env, images, plan.server, report);
          }
          await _pruneLocalTags(env, plan.local.keys, keep: 2);
        }),
      ),
    );
  }
  return steps;
}

Future<void> _syncGitContext(Ctx ctx, String dir, LocalContext c) async {
  if (!Directory(p.join(dir, '.git')).existsSync()) {
    Directory(p.dirname(dir)).createSync(recursive: true);
    await _run(ctx, 'git', ['clone', '-q', c.git!, dir], what: 'git clone');
  }
  await _run(ctx, 'git', ['-C', dir, 'fetch', '-q', 'origin', c.ref]);
  await _run(ctx, 'git', ['-C', dir, 'checkout', '-q', '-f', 'FETCH_HEAD']);
  final log = await Process.run('git', ['-C', dir, 'log', '--oneline', '-1']);
  ctx.log.info('${p.basename(dir)}: ${'${log.stdout}'.trim()}');
}

Future<void> _copyTree(String from, String to) async {
  if (Directory(to).existsSync()) Directory(to).deleteSync(recursive: true);
  Directory(p.dirname(to)).createSync(recursive: true);
  // APFS clones (cp -c) cost no space; elsewhere a plain copy.
  var r = await Process.run('cp', ['-Rc', from, to]);
  if (r.exitCode != 0) r = await Process.run('cp', ['-R', from, to]);
  if (r.exitCode != 0) throw Aborted('copy $from → $to failed: ${r.stderr}');
}

void _keepNewest(String dir, int keep, {bool files = false}) {
  final d = Directory(dir);
  if (!d.existsSync()) return;
  final all =
      d.listSync().where((e) => files ? e is File : e is Directory).toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  for (final x in all.skip(keep)) {
    x.deleteSync(recursive: true);
  }
}

/// Removes this machine's tags of [services] for [env] except the newest
/// [keep] releases. The server keeps its own copies.
Future<void> _pruneLocalTags(
  EnvConfig env,
  Iterable<String> services, {
  int keep = 2,
}) async {
  for (final s in services) {
    final repo = '${env.composeProject}-$s';
    final r = await Process.run('docker', [
      'images',
      '--format',
      '{{.Tag}}',
      repo,
    ]);
    final tags =
        '${r.stdout}'.split('\n').where((t) => t.trim().isNotEmpty).toList()
          ..sort((a, b) => b.compareTo(a));
    for (final t in tags.skip(keep)) {
      await Process.run('docker', ['image', 'rm', '$repo:$t']);
    }
  }
}

/// The remote script that tags images the server has by ID.
String retagScript(Map<String, String> nameToId) => [
  for (final e in nameToId.entries) 'docker tag ${shq(e.value)} ${shq(e.key)}',
  '',
].join('\n');

/// Sends [images] to the server of [env]: `docker save`, without the layers
/// the server has, compressed with zstd when both ends have it, then
/// `docker load`.
Future<void> shipByLoad(
  Ctx ctx,
  EnvConfig env,
  List<String> images,
  ServerDocker? server,
  ImageReport report,
) async {
  // Images the server has already (same ID) only need a new tag there.
  final ids = <String, String>{};
  for (final img in images) {
    final r = await Process.run('docker', [
      'image',
      'inspect',
      '--format',
      '{{.Id}}',
      img,
    ]);
    if (r.exitCode == 0) ids[img] = '${r.stdout}'.trim();
  }
  final known = await ctx.query(
    env,
    'docker images -q --no-trunc 2>/dev/null | sort -u\n',
  );
  final have = known.split('\n').map((l) => l.trim()).toSet();
  final retag = {
    for (final e in ids.entries)
      if (have.contains(e.value)) e.key: e.value,
  };
  if (retag.isNotEmpty) {
    await ctx.query(env, retagScript(retag));
    ctx.log.info(
      'already on ${env.host}, tagged there: ${retag.keys.join(', ')}',
    );
  }
  images = [
    for (final i in images)
      if (!retag.containsKey(i)) i,
  ];
  if (images.isEmpty) return;
  final tmp = await Directory.systemTemp.createTemp('podship-ship-');
  try {
    final tar = p.join(tmp.path, 'images.tar');
    await _run(ctx, 'docker', [
      'save',
      '-o',
      tar,
      ...images,
    ], what: 'docker save');
    final x = Directory(p.join(tmp.path, 'x'))..createSync();
    await _run(ctx, 'tar', ['-xf', tar, '-C', x.path], what: 'tar -x');
    File(tar).deleteSync();
    final saved = readArchive(x.path);
    var skip = <String>{};
    if (server?.containerdStore ?? false) {
      final ids = parseDiffIds(await ctx.query(env, serverDiffIdsScript));
      skip = blobsToSkip(saved, ids);
    }
    final all = archiveFiles(x.path, const {});
    final total = sizeOf(x.path, all);
    final zstd = (server?.zstd ?? false) && await _has('zstd');
    Future<bool> send(Set<String> leaveOut) async {
      final files = archiveFiles(x.path, leaveOut);
      final bytes = sizeOf(x.path, files);
      ctx.log.info(
        'sending ${mb(bytes)} of ${mb(total)}'
        '${leaveOut.isEmpty ? '' : ' (${leaveOut.length} layer(s) already on ${env.host})'}'
        '${zstd ? ', zstd' : ''}',
      );
      final list = File(p.join(tmp.path, 'files'))
        ..writeAsStringSync('${files.join('\n')}\n');
      final ok = await _pipeToServer(
        ctx,
        env,
        ['tar', '-cf', '-', '-C', x.path, '-T', list.path],
        zstd: zstd,
        remote: '${zstd ? 'zstd -dc | ' : ''}docker load',
      );
      if (ok) {
        report
          ..shippedBytes += bytes
          ..totalBytes += total
          ..layersSkipped += leaveOut.length;
      }
      return ok;
    }

    if (await send(skip)) return;
    if (skip.isEmpty) throw Aborted('docker load on ${env.host} failed');
    ctx.log.warn('the trimmed archive did not load: sending every layer');
    report.fullFallback = true;
    if (!await send(const {})) {
      throw Aborted('docker load on ${env.host} failed');
    }
  } finally {
    await tmp.delete(recursive: true);
  }
}

Future<bool> _has(String exe) async {
  try {
    final r = await Process.run(exe, ['--version']);
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Runs [producer] here and pipes its output (through zstd when [zstd]) to
/// [remote] on the server of [env]. Returns whether every part exited 0.
Future<bool> _pipeToServer(
  Ctx ctx,
  EnvConfig env,
  List<String> producer, {
  required bool zstd,
  required String remote,
}) async {
  final src = await Process.start(producer.first, producer.sublist(1));
  final mid = zstd
      ? await Process.start('zstd', ['-q', '-3', '-T0', '-c'])
      : null;
  final (exe, args) = ctx.ssh.command(env.host, ctx.header(env) + remote);
  final dst = await Process.start(exe, args);
  void pumpErr(Process pr) => pr.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => ctx.log.output(l, stderr: true));
  pumpErr(src);
  if (mid != null) pumpErr(mid);
  pumpErr(dst);
  dst.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => ctx.log.output(l));
  final f1 = mid == null
      ? src.stdout.pipe(dst.stdin)
      : Future.wait([src.stdout.pipe(mid.stdin), mid.stdout.pipe(dst.stdin)]);
  await f1;
  final codes = await Future.wait([src.exitCode, ?mid?.exitCode, dst.exitCode]);
  return codes.every((c) => c == 0);
}

/// Pushes [images] to the podship registry on this machine; the server
/// pulls them by digest through an ssh tunnel.
Future<void> shipByRegistry(
  Ctx ctx,
  EnvConfig env,
  List<String> images,
  ImageReport report,
) async {
  final port = env.build.registryPort;
  final auth = loadOrCreateAuth();
  await ensureRegistry(port, auth);
  await localLogin(port, auth);
  final registry = '127.0.0.1:$port';
  final refs = <String, String>{};
  for (final img in images) {
    final ref = '$registry/$img';
    await _run(ctx, 'docker', ['tag', img, ref]);
    final push = await Process.run('docker', ['push', ref]);
    if (push.exitCode != 0) {
      throw Aborted('docker push $ref failed: ${push.stderr}');
    }
    final m = RegExp(
      r'digest: (sha256:[0-9a-f]{64})',
    ).firstMatch('${push.stdout}');
    if (m == null) throw Aborted('docker push $ref: no digest in the output');
    final repo = img.substring(0, img.lastIndexOf(':'));
    refs['$registry/$repo@${m[1]}'] = img;
    await Process.run('docker', ['image', 'rm', ref]);
  }
  final script = ctx.header(env) + pullScript(registry, refs);
  // A connection of its own (no ControlMaster): the tunnel lives as long
  // as the pull.
  final opts = <String>[];
  final base = ctx.ssh.options();
  for (var i = 0; i < base.length; i++) {
    if (base[i] == '-o' && i + 1 < base.length) {
      if (!base[i + 1].startsWith('Control')) {
        opts.addAll([base[i], base[i + 1]]);
      }
      i++;
    } else {
      opts.add(base[i]);
    }
  }
  final args = [
    ...opts,
    '-o',
    'ControlPath=none',
    '-o',
    'ExitOnForwardFailure=yes',
    '-R',
    '127.0.0.1:$port:127.0.0.1:$port',
    env.host,
    'bash -c ${shq(script)}',
  ];
  final proc = await Process.start('ssh', args);
  proc.stdin.writeln(auth.password);
  await proc.stdin.close();
  final err = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => ctx.log.output(l, stderr: true));
  await proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((l) => ctx.log.output(l));
  await err.asFuture<void>();
  if (await proc.exitCode != 0) {
    throw Aborted('the pull from the podship registry on ${env.host} failed');
  }
  report.ship = 'registry';
}

/// Pushes [images] to GHCR with this machine's Docker login; the server
/// logs in with `gh auth token` (on stdin), pulls, and logs out.
Future<void> shipByGhcr(
  Ctx ctx,
  EnvConfig env,
  List<String> images,
  ImageReport report,
) async {
  final prefix = env.build.ghcr!;
  final token = await Process.run('gh', ['auth', 'token']);
  final user = await Process.run('gh', ['api', 'user', '-q', '.login']);
  if (token.exitCode != 0 || user.exitCode != 0) {
    throw Aborted('ship ghcr needs the gh CLI logged in (gh auth login)');
  }
  final refs = <String, String>{};
  for (final img in images) {
    final ref = '$prefix/$img';
    await _run(ctx, 'docker', ['tag', img, ref]);
    final push = await Process.run('docker', ['push', ref]);
    if (push.exitCode != 0) throw Aborted('docker push $ref: ${push.stderr}');
    final m = RegExp(
      r'digest: (sha256:[0-9a-f]{64})',
    ).firstMatch('${push.stdout}');
    final repo = ref.substring(0, ref.lastIndexOf(':'));
    refs[m == null ? ref : '$repo@${m[1]}'] = img;
  }
  final host = prefix.split('/').first;
  final script = pullScript(
    host,
    refs,
  ).replaceFirst('-u $registryUser', '-u ${shq('${user.stdout}'.trim())}');
  await ctx.ssh.capture(
    env.host,
    ctx.header(env) + script,
    stdin: utf8.encode('${'${token.stdout}'.trim()}\n'),
  );
  report.ship = 'ghcr';
}

/// One line of `docker system df --format '{{json .}}'`.
class DiskUse {
  DiskUse(this.type, this.bytes, this.reclaimable);
  final String type;
  final int bytes;
  final int reclaimable;
}

/// Parses Docker sizes like `40.96GB`, `911.5MB (2%)`, `0B`.
int parseDockerSize(String s) {
  final m = RegExp(r'([\d.]+)\s*([kKMGT]?B)').firstMatch(s);
  if (m == null) return 0;
  final v = double.parse(m[1]!);
  final mult = switch (m[2]!.toUpperCase()) {
    'KB' => 1e3,
    'MB' => 1e6,
    'GB' => 1e9,
    'TB' => 1e12,
    _ => 1.0,
  };
  return (v * mult).round();
}

/// Parses `docker system df --format '{{json .}}'`.
List<DiskUse> parseSystemDf(String out) => [
  for (final line in out.split('\n'))
    if (line.trim().startsWith('{'))
      () {
        final j = jsonDecode(line) as Map<String, Object?>;
        return DiskUse(
          '${j['Type']}',
          parseDockerSize('${j['Size']}'),
          parseDockerSize('${j['Reclaimable']}'),
        );
      }(),
];

int _total(List<DiskUse> d) => d.fold(0, (a, x) => a + x.bytes);

/// The remote script of [serverHygiene], without the `docker system df`
/// calls around it.
String hygieneScript({
  required List<String> repos,
  required List<String> keepTags,
  required bool buildCache,
}) {
  final b = StringBuffer()
    ..writeln('used=" \$(docker ps -a --format "{{.Image}}" | tr "\\n" " ") "')
    ..writeln('docker image prune -f >/dev/null');
  final keep = keepTags.map(shq).join(' ');
  for (final repo in repos) {
    b
      ..writeln(
        'for t in \$(docker images --format "{{.Tag}}" ${shq(repo)}); do',
      )
      ..writeln('  case " $keep " in *" \$t "*) continue;; esac')
      ..writeln(
        '  case "\$used" in *" ${repo.replaceAll('"', '')}:\$t "*) continue;; esac',
      )
      ..writeln(
        '  docker image rm ${shq(repo)}:"\$t" >/dev/null 2>&1 && echo "removed $repo:\$t" || true',
      )
      ..writeln('done');
  }
  if (buildCache) {
    b
      ..writeln('# The Dart SDK and the build cache are only for building.')
      ..writeln(
        'for img in \$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^(dart|docker.io/library/dart):" || true); do',
      )
      ..writeln('  case "\$used" in *" \$img "*) continue;; esac')
      ..writeln(
        '  docker image rm "\$img" >/dev/null 2>&1 && echo "removed \$img" || true',
      )
      ..writeln('done')
      ..writeln('docker builder prune -af 2>/dev/null | tail -1 || true');
  }
  return b.toString();
}

/// Removes, on the server of [env], the images of this environment that no
/// kept release uses, dangling images, and (when the server no longer
/// builds) the Dart SDK images and the build cache. Logs the disk saved.
Future<void> serverHygiene(
  Ctx ctx,
  EnvConfig env, {
  required List<String> services,
  required List<String> keepReleases,
  required bool buildCache,
}) async {
  const df = "docker system df --format '{{json .}}'\n";
  final before = parseSystemDf(await ctx.query(env, df));
  final out = await ctx.query(
    env,
    hygieneScript(
      repos: [for (final s in services) '${env.composeProject}-$s'],
      keepTags: keepReleases,
      buildCache: buildCache,
    ),
  );
  for (final l in out.split('\n')) {
    if (l.trim().isNotEmpty) ctx.log.info(l.trim());
  }
  final after = parseSystemDf(await ctx.query(env, df));
  final saved = _total(before) - _total(after);
  String row(String type) {
    final a = before.where((x) => x.type == type).firstOrNull?.bytes ?? 0;
    final z = after.where((x) => x.type == type).firstOrNull?.bytes ?? 0;
    return '$type ${mb(a)} → ${mb(z)}';
  }

  ctx.log.info(
    'disk on ${env.host}: saved ${mb(saved < 0 ? 0 : saved)} '
    '(${row('Images')}; ${row('Build Cache')})',
  );
}
