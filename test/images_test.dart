@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/config/config.dart';
import 'package:podship/src/images/archive.dart';
import 'package:podship/src/images/dockerfile.dart';
import 'package:podship/src/images/images.dart';
import 'package:podship/src/images/registry.dart';
import 'package:podship/src/images/target.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/plan/executor.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// CazaFacturas' server Dockerfile (2026-10-08), shortened.
const cazaDockerfile = r'''
FROM dart:3.12.2 AS build
WORKDIR /app
COPY pubspec.lock .
COPY cazafacturas_server/pubspec.yaml cazafacturas_server/pubspec.yaml
RUN --mount=type=cache,target=/root/.pub-cache,sharing=locked dart pub get
COPY cazafacturas_server/bin cazafacturas_server/bin
COPY cazafacturas_server/lib cazafacturas_server/lib
WORKDIR /app/cazafacturas_server
RUN --mount=type=cache,target=/root/.pub-cache,sharing=locked \
    dart build cli --target bin/main.dart --output build && \
    mv build/bundle/bin/main build/bundle/bin/server

# Final stage
FROM alpine:3.22
WORKDIR /app
ENV runmode=production
COPY --from=build /runtime/ /
COPY --from=build /app/cazafacturas_server/build/bundle/ ./
COPY cazafacturas_server/lib/src/generated/protocol.yaml lib/src/generated/protocol.yaml
COPY cazafacturas_server/config/ config/
COPY cazafacturas_server/web/ web/
EXPOSE 8082
ENTRYPOINT ./bin/server --mode=$runmode
''';

/// Boceto's server Dockerfile (2026-10-08), shortened.
const bocetoDockerfile = r'''
FROM dart:3.12.2 AS build
WORKDIR /app
COPY pubspec.lock .
COPY boceto_server boceto_server
RUN dart pub get
WORKDIR /app/boceto_server
RUN dart build cli --target bin/main.dart --output build
RUN mv build/bundle/bin/main build/bundle/bin/server

FROM alpine:3.22
RUN apk add --no-cache git openssh-client ca-certificates tzdata
WORKDIR /app
COPY --from=build /runtime/ /
COPY --from=build /app/boceto_server/build/bundle/ ./
COPY --from=build /app/boceto_server/config/ config/
COPY --from=build /app/boceto_server/web/ web/
COPY --from=build /app/boceto_server/lib/src/generated/protocol.yaml lib/src/generated/protocol.yaml
ENTRYPOINT ./bin/server --mode=$runmode --apply-migrations
''';

HostTools mac({String? dart = '3.13.2', bool buildx = true}) => HostTools(
  os: 'macos',
  arch: 'arm64',
  dartVersion: dart,
  docker: true,
  buildx: buildx,
  dockerPlatform: const DockerPlatform('linux', 'arm64'),
);

void main() {
  group('build location', () {
    const amd = DockerPlatform('linux', 'amd64');
    const arm = DockerPlatform('linux', 'arm64');

    test('platforms and archs normalize', () {
      expect(DockerPlatform.parse('linux/x86_64'), amd);
      expect(DockerPlatform.parse('linux/aarch64'), arm);
      expect(amd.dartArch, 'x64');
      expect(DockerPlatform.parse('nonsense'), isNull);
    });

    test('server probe output parses', () {
      final s = ServerDocker.parse(
        'uname=arm64\nplatform=linux/arm64\nos=Docker Desktop\n'
        'driver=[["driver-type","io.containerd.snapshotter.v1"]]\nzstd=yes\n',
      );
      expect(s.platform, arm);
      expect(s.dockerDesktop, isTrue);
      expect(s.containerdStore, isTrue);
      expect(s.zstd, isTrue);
      final vps = ServerDocker.parse('uname=x86_64\nplatform=\nos=Ubuntu\n');
      expect(vps.platform, amd);
      expect(vps.dockerDesktop, isFalse);
    });

    test('a Mac cross-compiles for an x86_64 server', () {
      final d = decideBuild(
        requested: BuildLocation.auto,
        host: mac(),
        platform: amd,
      );
      expect(d.location, BuildLocation.local);
      expect(d.cross, isTrue);
      expect(d.reason, contains('cross-compiles'));
    });

    test('a Linux machine compiles natively for the same platform', () {
      final d = decideBuild(
        requested: BuildLocation.local,
        host: HostTools(
          os: 'linux',
          arch: 'amd64',
          dartVersion: '3.5.0',
          docker: true,
          buildx: true,
        ),
        platform: amd,
      );
      expect(d.location, BuildLocation.local);
      expect(d.cross, isFalse);
    });

    test('old Dart or no Dart falls back to local-docker', () {
      expect(
        decideBuild(
          requested: BuildLocation.auto,
          host: mac(dart: '3.5.0'),
          platform: amd,
        ).location,
        BuildLocation.localDocker,
      );
      final d = decideBuild(
        requested: BuildLocation.auto,
        host: mac(dart: null),
        platform: amd,
      );
      expect(d.location, BuildLocation.localDocker);
      expect(d.reason, contains('no dart'));
      expect(d.reason, contains('emulated'));
    });

    test('local-docker when asked', () {
      expect(
        decideBuild(
          requested: BuildLocation.localDocker,
          host: mac(),
          platform: arm,
        ).location,
        BuildLocation.localDocker,
      );
    });

    test('falls back to remote with the reason', () {
      expect(
        decideBuild(
          requested: BuildLocation.remote,
          host: mac(),
          platform: arm,
        ).location,
        BuildLocation.remote,
      );
      final nobx = decideBuild(
        requested: BuildLocation.auto,
        host: mac(buildx: false),
        platform: arm,
      );
      expect(nobx.location, BuildLocation.remote);
      expect(nobx.reason, contains('buildx'));
      final nodocker = decideBuild(
        requested: BuildLocation.local,
        host: HostTools(os: 'macos', arch: 'arm64', dartVersion: '3.13.0'),
        platform: arm,
      );
      expect(nodocker.location, BuildLocation.remote);
      expect(nodocker.reason, contains('Docker does not answer'));
    });
  });

  group('runtime Dockerfile', () {
    test('CazaFacturas: the build stage becomes local files', () {
      final r = runtimeDockerfile(
        cazaDockerfile,
        bundleDir: '.podship-image/bundle',
      );
      expect(r.builderImage, 'dart:3.12.2');
      expect(r.renames, {'bin/main': 'bin/server'});
      expect(r.hasRun, isFalse);
      final t = r.text;
      expect(t, contains('FROM alpine:3.22'));
      expect(t, isNot(contains('FROM dart')));
      expect(t, contains('COPY --from=dart:3.12.2 /runtime/ /'));
      expect(t, contains('COPY .podship-image/bundle/ ./'));
      expect(t, contains('COPY cazafacturas_server/web/ web/'));
      expect(t, contains('ENTRYPOINT ./bin/server --mode=\$runmode'));
      expect(t, isNot(contains('--from=build')));
    });

    test('Boceto: paths copied by the build stage map to the context', () {
      final r = runtimeDockerfile(
        bocetoDockerfile,
        bundleDir: '.podship-image/bundle',
      );
      expect(r.hasRun, isTrue);
      expect(r.renames, {'bin/main': 'bin/server'});
      final t = r.text;
      expect(t, contains('COPY boceto_server/config/ config/'));
      expect(t, contains('COPY boceto_server/web/ web/'));
      expect(
        t,
        contains(
          'COPY boceto_server/lib/src/generated/protocol.yaml lib/src/generated/protocol.yaml',
        ),
      );
      expect(t, contains('RUN apk add'));
      expect(t, contains('--apply-migrations'));
    });

    test('JIT adds the Dart VM from the build image', () {
      final r = runtimeDockerfile(
        cazaDockerfile,
        bundleDir: '.podship-image/bundle',
        jitKernel: true,
      );
      expect(
        r.text,
        contains(
          'COPY --from=dart:3.12.2 /usr/lib/dart/bin/dart /usr/lib/dart/bin/dart',
        ),
      );
    });

    test('a path podship cannot place asks for local-docker', () {
      expect(
        () => runtimeDockerfile(
          'FROM dart AS b\nRUN dart build cli\nFROM alpine\nCOPY --from=b /opt/x /x\n',
          bundleDir: 'b',
        ),
        throwsA(
          isA<DockerfileException>().having(
            (e) => e.message,
            'message',
            contains('local-docker'),
          ),
        ),
      );
      expect(
        () => runtimeDockerfile('FROM alpine\n', bundleDir: 'b'),
        throwsA(isA<DockerfileException>()),
      );
    });

    test('compose build sections, later files win', () {
      final b = serviceBuilds([
        'services:\n  server:\n    build: {context: ., dockerfile: s/Dockerfile, args: {A: "1"}}\n'
            '  chrome:\n    build: ./docker/chrome\n  postgres:\n    image: postgres\n',
        'services:\n  chrome:\n    platform: linux/amd64\n',
      ]);
      expect(b.keys, unorderedEquals(['server', 'chrome']));
      expect(b['server']!.dockerfilePath, 's/Dockerfile');
      expect(b['server']!.args, {'A': '1'});
      expect(b['chrome']!.platform, 'linux/amd64');
      expect(b['chrome']!.dockerfilePath, 'docker/chrome/Dockerfile');
    });
  });

  group('layer dedupe', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('podship-archive-');
      final blobs = Directory(p.join(dir.path, 'blobs', 'sha256'))
        ..createSync(recursive: true);
      void blob(String name, Object content) => File(
        p.join(blobs.path, name),
      ).writeAsStringSync(content is String ? content : jsonEncode(content));
      blob('cfgA', {
        'rootfs': {
          'diff_ids': ['sha256:base', 'sha256:appA'],
        },
      });
      blob('cfgB', {
        'rootfs': {
          'diff_ids': ['sha256:base', 'sha256:appB'],
        },
      });
      blob('L1', 'base layer');
      blob('L2', 'app A');
      blob('L3', 'app B');
      File(p.join(dir.path, 'manifest.json')).writeAsStringSync(
        jsonEncode([
          {
            'Config': 'blobs/sha256/cfgA',
            'RepoTags': ['x-server:1'],
            'Layers': ['blobs/sha256/L1', 'blobs/sha256/L2'],
          },
          {
            'Config': 'blobs/sha256/cfgB',
            'RepoTags': ['x-chrome:1'],
            'Layers': ['blobs/sha256/L1', 'blobs/sha256/L3'],
          },
        ]),
      );
      File(p.join(dir.path, 'index.json')).writeAsStringSync('{}');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads the archive and maps layers to DiffIDs', () {
      final imgs = readArchive(dir.path);
      expect(imgs, hasLength(2));
      expect(imgs.first.tags, ['x-server:1']);
      expect(imgs.first.diffIds, ['sha256:base', 'sha256:appA']);
    });

    test('leaves out only the layers the server has', () {
      final imgs = readArchive(dir.path);
      final skip = blobsToSkip(imgs, {'sha256:base', 'sha256:old'});
      expect(skip, {'blobs/sha256/L1'});
      final files = archiveFiles(dir.path, skip);
      expect(files, isNot(contains('blobs/sha256/L1')));
      expect(files, containsAll(['manifest.json', 'blobs/sha256/cfgA']));
      expect(blobsToSkip(imgs, {}), isEmpty);
    });

    test('server DiffIDs parse from docker inspect output', () {
      expect(parseDiffIds('["sha256:a","sha256:b"]\n\n["sha256:a"]\nnoise\n'), {
        'sha256:a',
        'sha256:b',
      });
    });
  });

  group('registry', () {
    test('htpasswd accepts the right password only', () {
      final a = RegistryAuth.generate();
      expect(a.password.length, greaterThanOrEqualTo(40));
      final line = a.htpasswd(rounds: 4);
      expect(line, startsWith('podship:\$2'));
      expect(htpasswdAccepts(line, 'podship', a.password), isTrue);
      expect(htpasswdAccepts(line, 'podship', 'wrong'), isFalse);
      expect(htpasswdAccepts(line, 'other', a.password), isFalse);
    });

    test('the login is created once and kept', () {
      final d = Directory.systemTemp.createTempSync('podship-reg-');
      try {
        final a = loadOrCreateAuth(d.path);
        final b = loadOrCreateAuth(d.path);
        expect(b.password, a.password);
        final mode = File(
          p.join(d.path, 'credentials'),
        ).statSync().modeString();
        expect(mode, 'rw-------');
      } finally {
        d.deleteSync(recursive: true);
      }
    });

    test(
      'the pull script reads the password from stdin and pulls by digest',
      () {
        final s = pullScript('127.0.0.1:5480', {
          '127.0.0.1:5480/x-server@sha256:abc': 'x-server:r1',
        });
        expect(s, startsWith('IFS= read -r PODSHIP_REGISTRY_PASSWORD'));
        expect(s, contains('--password-stdin'));
        expect(
          s,
          contains('docker pull -q 127.0.0.1:5480/x-server@sha256:abc'),
        );
        expect(
          s,
          contains('docker tag 127.0.0.1:5480/x-server@sha256:abc x-server:r1'),
        );
        expect(s, contains('docker logout'));
      },
    );

    test('the registry listens on loopback only, with auth', () {
      final args = registryRunArgs(5480, '/h/.podship/registry').join(' ');
      expect(args, contains('-p 127.0.0.1:5480:5000'));
      expect(args, contains('REGISTRY_AUTH=htpasswd'));
    });
  });

  group('config', () {
    String withBuild(String build, {String env = 'staging'}) =>
        sampleConfig.replaceFirst(
          '  $env:\n    host: prod-box\n',
          '  $env:\n    host: prod-box\n$build',
        );

    test('defaults to auto, aot, auto ship', () {
      final c = PodshipConfig.parse(sampleConfig);
      final b = c.env('production').build;
      expect(b.location, BuildLocation.auto);
      expect(b.mode, CompileMode.aot);
      expect(b.ship, ShipMethod.auto);
      expect(c.env('production').switchMode, SwitchMode.inPlace);
    });

    test('scalar and map forms', () {
      expect(
        PodshipConfig.parse(
          withBuild('    build: local-docker\n'),
        ).env('staging').build.location,
        BuildLocation.localDocker,
      );
      final b = PodshipConfig.parse(
        withBuild(
          '    build:\n      location: local\n      mode: jit\n      ship: registry\n'
          '      platform: linux/amd64\n      contexts:\n        worker: {git: git@x:y.git, ref: dev}\n'
          '        other: ../other\n',
        ),
      ).env('staging').build;
      expect(b.mode, CompileMode.jit);
      expect(b.ship, ShipMethod.registry);
      expect(b.platform, 'linux/amd64');
      expect(b.contexts['worker']!.git, 'git@x:y.git');
      expect(b.contexts['worker']!.ref, 'dev');
      expect(b.contexts['other']!.path, '../other');
    });

    test('production is always aot; bad values fail', () {
      expect(
        () => PodshipConfig.parse(
          withBuild('    build: {mode: jit}\n', env: 'production'),
        ),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => PodshipConfig.parse(withBuild('    build: anywhere\n')),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => PodshipConfig.parse(withBuild('    build: {ship: ghcr}\n')),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('parallel step', () {
    test('runs lanes at the same time and fails after all stop', () async {
      final order = <String>[];
      final ex = Executor(Ssh(), Log.silent());
      Future<void> slow(String name, int ms) async {
        order.add('start $name');
        await Future<void>.delayed(Duration(milliseconds: ms));
        order.add('end $name');
      }

      await ex.runStep(
        ParallelStep('p', [
          Lane('a', [ActionStep('a1', '', () => slow('a', 40))]),
          Lane('b', [ActionStep('b1', '', () => slow('b', 5))]),
        ]),
      );
      expect(order, ['start a', 'start b', 'end b', 'end a']);

      var after = false;
      await expectLater(
        ex.runStep(
          ParallelStep('p', [
            Lane('bad', [ActionStep('x', '', () async => throw Aborted('no'))]),
            Lane('ok', [
              ActionStep('y', '', () async {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                after = true;
              }),
            ]),
          ]),
        ),
        throwsA(isA<StepError>()),
      );
      expect(after, isTrue);
    });
  });

  group('deploy plan with local images', () {
    final config = PodshipConfig.parse(sampleConfig, root: '/work/demo');
    final ctx = Ctx(
      config: config,
      ssh: Ssh(),
      log: Log.silent(),
      dryRun: true,
    );
    final s = parseState(
      'CURRENT 20261002-000000-bbbbbbb\n'
      'R 20261002-000000-bbbbbbb ok {"id":"x","sha":"abc","images":[]}\n'
      'ENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
    );
    final r = resolveEnv(
      config,
      config.env('production'),
      s.registry,
      listening: s.listening,
    );
    ImagePlan images({Map<String, String> remote = const {}}) => ImagePlan(
      decision: BuildDecision(
        BuildLocation.local,
        'cross',
        platform: const DockerPlatform('linux', 'amd64'),
        cross: true,
      ),
      ship: 'load',
      shipReason: 'save/load',
      local: {'server': ServiceBuild(service: 'server', context: '.')},
      remote: remote,
      runtime: runtimeDockerfile(cazaDockerfile, bundleDir: 'b'),
    );
    Plan plan(ImagePlan i) => planDeploy(
      ctx: ctx,
      r: r,
      state: s,
      git: GitInfo('a0dc2b0123456789', ref: 'main'),
      now: DateTime.utc(2026, 10, 6, 16),
      snapshot: '/tmp/snap',
      options: DeployOptions(images: i),
    );

    test(
      'tests, images and backup run in parallel; the server builds nothing',
      () {
        final pl = plan(images());
        final titles = pl.steps.map((x) => x.title).toList();
        expect(titles, contains('Tests, images and backup'));
        expect(titles, isNot(contains('Build images on the server')));
        expect(titles, isNot(contains('Build Flutter web: app')));
        expect(
          titles,
          isNot(contains('Back up the database before the switch')),
        );
        expect(titles.last, 'Server hygiene on prod-box');
        final par = pl.steps.whereType<ParallelStep>().single;
        expect(par.lanes.map((l) => l.name), ['images', 'backup']);
        final img = par.lanes.first.steps.map((x) => x.title).toList();
        expect(img, [
          'Export for the image build',
          'Flutter web: app',
          'Compile the server for linux/amd64',
          'Build image server for linux/amd64',
          'Ship images to prod-box (load)',
        ]);
        // The switch is still guarded after the parallel stage.
        expect(pl.steps[pl.guardFrom!].title, startsWith('Switch to'));
      },
    );

    test('a service with a server-only context still builds there', () {
      final pl = plan(images(remote: {'worker': 'server path'}));
      final titles = pl.steps.map((x) => x.title).toList();
      expect(titles, contains('Build worker on the server'));
    });

    test('hygiene keeps the kept releases and drops the build cache', () {
      final t = hygieneScript(
        repos: ['demo-server'],
        keepTags: ['r1', 'r2'],
        buildCache: true,
      );
      expect(t, contains('case " r1 r2 "'));
      expect(t, contains('docker builder prune -af'));
      expect(t, contains('dart'));
      expect(
        hygieneScript(repos: ['x'], keepTags: [], buildCache: false),
        isNot(contains('builder prune')),
      );
    });

    test('docker sizes parse', () {
      expect(parseDockerSize('40.96GB'), 40960000000);
      expect(parseDockerSize('911.5MB (2%)'), 911500000);
      expect(parseDockerSize('0B'), 0);
      final d = parseSystemDf(
        '{"Type":"Images","Size":"1.5GB","Reclaimable":"1GB (66%)"}\n',
      );
      expect(d.single.bytes, 1500000000);
      expect(d.single.reclaimable, 1000000000);
    });
  });
}
