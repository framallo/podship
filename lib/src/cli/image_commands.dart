// `podship images check` and `podship images prune`.

import 'dart:io';

import '../config/config.dart';
import '../images/archive.dart';
import '../images/images.dart';
import '../images/stack.dart';
import '../ops/context.dart';
import '../ops/deploy.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../util/temp.dart';
import 'base.dart';

/// Builds the images of the current commit on this machine, ships them to
/// the server of --env, starts the server image there in a throwaway stack
/// (its own network and Postgres, a test port on loopback), checks
/// /health, then removes everything. No release, no switch, no DNS.
class ImagesCheckCommand extends PodshipCommand {
  ImagesCheckCommand() {
    argParser
      ..addOption(
        'services',
        defaultsTo: 'server',
        help:
            'Comma-separated services to build and ship (default: the server).',
      )
      ..addOption(
        'port',
        defaultsTo: '18099',
        help: 'The loopback port on the server for the health check.',
      )
      ..addOption('ref', help: 'The git ref (default: build.ref).')
      ..addOption(
        'ship',
        allowed: ['load', 'registry', 'ghcr'],
        help: 'Override build.ship for this check.',
      )
      ..addFlag('keep-images', help: 'Leave the check images on the server.');
  }

  @override
  String get name => 'check';
  @override
  String get description =>
      'Build the images here, ship them to --env, start the server image on a test port with a throwaway Postgres, check /health, remove it all.';

  @override
  Future<int> execute() async {
    final e = env;
    final c = ctx;
    final ref = argResults!['ref'] as String? ?? config.build.ref;
    final git = await GitInfo.read(config.root, ref);
    if (git.sha == 'nogit') throw Aborted('ref "$ref" not found');
    final full = await computeImagePlan(ctx: c, env: e, sha: git.sha);
    c.log.info(full.decision.reason);
    if (!full.decision.local) return 1;
    final wanted = (argResults!['services'] as String)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final plan = ImagePlan(
      decision: full.decision,
      ship: argResults!['ship'] as String? ?? full.ship,
      shipReason: argResults!['ship'] == null
          ? full.shipReason
          : '--ship ${argResults!['ship']}',
      local: {
        for (final x in full.local.entries)
          if (wanted.contains(x.key)) x.key: x.value,
      },
      runtime: full.runtime,
      server: full.server,
      jit: full.jit,
      mainTarget: full.mainTarget,
      serverKey: full.serverKey,
      report: full.report,
    );
    if (plan.local.isEmpty) {
      throw Aborted('none of ${wanted.join(', ')} builds on this machine');
    }
    final sha7 = git.sha.substring(0, 7);
    final release =
        'check-${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14)}-$sha7';
    final dir = await createExportDir('podship-check-');
    final imgRoot = '${dir.path}.image';
    final images = [
      for (final s in plan.local.keys) imageName(e.composeProject, s, release),
    ];
    final port = int.parse(argResults!['port'] as String);
    final id = 'check-$sha7';
    final watch = Stopwatch()..start();
    try {
      final steps = imageLane(
        ctx: c,
        env: e,
        plan: plan,
        release: release,
        imgRoot: imgRoot,
        sha: git.sha,
        runGate: false,
        export: () => exportCommit(config.root, git.sha, imgRoot),
      );
      await c.run(Plan('images check ${e.name} ($sha7)', steps));
      if (dryRun) return 0;
      final build = watch.elapsed;
      if (plan.local.containsKey(e.serverService)) {
        final gate = config.tests.imageGate;
        final def = defaultStack(
          e,
          passwordKeys: {
            for (final x in config.environments.values)
              ...x.secrets.passwordKeys,
          },
        );
        final server = gate?.server ?? StackServer();
        final services = gate?.services ?? def.services;
        final up = stackUpScript(
          id: id,
          serverImage: imageName(e.composeProject, e.serverService, release),
          server: server.withEnv(def.env),
          services: services,
          publish: port,
        );
        try {
          await c.query(e, stackDownScript(id));
          final out = await c.query(e, up);
          stdout.write(out);
          final health = await c.query(
            e,
            'curl -fsS -o /dev/null -w "%{http_code}" http://127.0.0.1:$port${server.health}\n',
          );
          c.log.info(
            'http://127.0.0.1:$port${server.health} on ${e.host}: $health',
          );
        } finally {
          await c.query(e, stackDownScript(id));
        }
      }
      final r = plan.report;
      stdout.writeln('\nimages check ${e.name} on ${e.host}:');
      stdout.writeln('  build: ${plan.decision.reason}');
      stdout.writeln('  ship:  ${plan.shipReason}');
      for (final s in r.sizes.entries) {
        stdout.writeln('  ${s.key.padRight(12)} ${mb(s.value)} (here)');
      }
      if (r.totalBytes > 0) {
        stdout.writeln(
          '  sent ${mb(r.shippedBytes)} of ${mb(r.totalBytes)} (${r.layersSkipped} layers already there)',
        );
      }
      stdout.writeln(
        '  times: ${r.millis.entries.map((x) => '${x.key} ${(x.value / 1000).toStringAsFixed(1)} s').join(', ')}; '
        'build+ship ${(build.inMilliseconds / 1000).toStringAsFixed(1)} s, total ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
      );
      return 0;
    } finally {
      if (!(argResults!['keep-images'] as bool) && !dryRun) {
        await c.query(
          e,
          'for i in ${images.join(' ')}; do docker image rm "\$i" >/dev/null 2>&1 || true; done\n',
        );
        for (final i in images) {
          await Process.run('docker', ['image', 'rm', i]);
        }
      }
      await dir.delete(recursive: true);
      if (Directory(imgRoot).existsSync()) {
        await Directory(imgRoot).delete(recursive: true);
      }
    }
  }
}

/// Removes old images, the Dart SDK images and the build cache on the
/// server of --env, and says how much disk that saved.
class ImagesPruneCommand extends PodshipCommand {
  ImagesPruneCommand() {
    argParser.addFlag(
      'build-cache',
      defaultsTo: true,
      help: 'Also remove the build cache and the Dart SDK images.',
    );
  }
  @override
  bool get mutating => true;
  @override
  String get name => 'prune';
  @override
  String get description =>
      'Remove images no kept release uses (and the build cache) on the server of --env; report the disk saved.';

  @override
  Future<int> execute() async {
    final e = env;
    final out = await ctx.query(
      e,
      'ls -1 ${e.dir}/releases 2>/dev/null || true\n',
    );
    final kept = out.split('\n').where((x) => x.trim().isNotEmpty).toList();
    final services = await ctx.query(
      e,
      'docker images --format "{{.Repository}}" | sort -u\n',
    );
    final repos = [
      for (final r in services.split('\n'))
        if (r.startsWith('${e.composeProject}-'))
          r.substring(e.composeProject.length + 1),
    ];
    if (dryRun) {
      stdout.writeln(
        hygieneScript(
          repos: [for (final s in repos) '${e.composeProject}-$s'],
          keepTags: kept,
          buildCache: argResults!['build-cache'] as bool,
        ),
      );
      return 0;
    }
    await serverHygiene(
      ctx,
      e,
      services: repos,
      keepReleases: kept,
      buildCache: argResults!['build-cache'] as bool,
    );
    return 0;
  }
}
