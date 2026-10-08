// Where images are built: this machine or the server.
//
// The server only runs the app. This machine (a laptop or a build Mac) has
// more CPU and disk, and it keeps the build caches. podship asks the
// server's Docker for its platform, looks at the tools on this machine,
// and picks a build location. Pure functions here; the probes that fill
// them are at the end.

import 'dart:io';

import '../config/config.dart';
import '../ops/context.dart';

/// A Docker platform, like `linux/amd64`.
class DockerPlatform {
  const DockerPlatform(this.os, this.arch);

  /// Parses `linux/amd64`, `linux/aarch64`, `linux/x86_64`.
  static DockerPlatform? parse(String s) {
    final parts = s.trim().split('/');
    if (parts.length < 2) return null;
    final arch = normalizeArch(parts[1]);
    if (arch == null) return null;
    return DockerPlatform(parts[0].toLowerCase(), arch);
  }

  final String os;

  /// `amd64` or `arm64`.
  final String arch;

  /// The `--target-arch` of `dart build cli`.
  String get dartArch => arch == 'amd64' ? 'x64' : 'arm64';

  @override
  String toString() => '$os/$arch';

  @override
  bool operator ==(Object other) =>
      other is DockerPlatform && other.os == os && other.arch == arch;

  @override
  int get hashCode => Object.hash(os, arch);
}

/// `x86_64`/`amd64`/`x64` → `amd64`; `aarch64`/`arm64` → `arm64`.
String? normalizeArch(String a) => switch (a.trim().toLowerCase()) {
  'x86_64' || 'amd64' || 'x64' => 'amd64',
  'aarch64' || 'arm64' || 'arm64/v8' => 'arm64',
  _ => null,
};

/// What the server's Docker says about itself.
class ServerDocker {
  ServerDocker({
    required this.platform,
    this.uname = '',
    this.operatingSystem = '',
    this.containerdStore = false,
    this.zstd = false,
  });

  /// Parses the output of [serverProbeScript].
  static ServerDocker parse(String out) {
    final m = <String, String>{};
    for (final l in out.split('\n')) {
      final i = l.indexOf('=');
      if (i > 0) m[l.substring(0, i).trim()] = l.substring(i + 1).trim();
    }
    final platform =
        DockerPlatform.parse(m['platform'] ?? '') ??
        DockerPlatform('linux', normalizeArch(m['uname'] ?? '') ?? 'amd64');
    return ServerDocker(
      platform: platform,
      uname: m['uname'] ?? '',
      operatingSystem: m['os'] ?? '',
      containerdStore: (m['driver'] ?? '').contains('containerd'),
      zstd: m['zstd'] == 'yes',
    );
  }

  final DockerPlatform platform;

  /// `uname -m` of the host (Docker Desktop on a Mac says arm64 here, and
  /// linux/arm64 for its Docker).
  final String uname;

  /// `docker info` OperatingSystem, like `Docker Desktop` or `Ubuntu 24.04`.
  final String operatingSystem;

  /// Whether images live in containerd's content store. Then `docker load`
  /// accepts an archive without the layers the server already has.
  final bool containerdStore;

  /// Whether `zstd` is on the server.
  final bool zstd;

  /// Docker Desktop runs the daemon in a VM: its 127.0.0.1 is not the
  /// host's, so a registry reached through an ssh tunnel is out of reach.
  bool get dockerDesktop =>
      operatingSystem.toLowerCase().contains('docker desktop');
}

/// The script whose output [ServerDocker.parse] reads.
const serverProbeScript = r'''
echo "uname=$(uname -m)"
echo "platform=$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}' 2>/dev/null)"
echo "os=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null)"
echo "driver=$(docker info --format '{{json .DriverStatus}}' 2>/dev/null)"
command -v zstd >/dev/null 2>&1 && echo "zstd=yes" || echo "zstd=no"
''';

/// The tools on this machine.
class HostTools {
  HostTools({
    required this.os,
    required this.arch,
    this.dartVersion,
    this.docker = false,
    this.buildx = false,
    this.dockerPlatform,
  });

  /// `macos`, `linux`, …
  final String os;

  /// `amd64` or `arm64`.
  final String arch;

  /// Like `3.13.2`; null when `dart` is missing.
  final String? dartVersion;
  final bool docker;
  final bool buildx;

  /// The platform of the local Docker (Colima or Docker Desktop on a Mac:
  /// linux/arm64).
  final DockerPlatform? dockerPlatform;

  /// Whether `dart build cli` can compile for [target]: on the same OS and
  /// CPU, or by cross-compilation (Dart 3.8 and later, Linux targets).
  bool canCompileFor(DockerPlatform target) {
    final v = dartVersion;
    if (v == null) return false;
    if (os == target.os && arch == target.arch) return true;
    return target.os == 'linux' && versionAtLeast(v, 3, 8);
  }
}

/// Whether the version string [v] (like `3.13.2`) is at least
/// [major].[minor].
bool versionAtLeast(String v, int major, int minor) {
  final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(v);
  if (m == null) return false;
  final a = int.parse(m[1]!), b = int.parse(m[2]!);
  return a > major || (a == major && b >= minor);
}

/// Where the images of one deploy are built, and why.
class BuildDecision {
  BuildDecision(
    this.location,
    this.reason, {
    required this.platform,
    this.cross = false,
  });

  /// [BuildLocation.local], [BuildLocation.localDocker] or
  /// [BuildLocation.remote]; never auto.
  final BuildLocation location;

  /// One line for the log: why this location.
  final String reason;

  /// The platform of the server's Docker.
  final DockerPlatform platform;

  /// Whether the server binary is cross-compiled.
  final bool cross;

  bool get local => location != BuildLocation.remote;

  String get name => EnvBuild.locationName(location);
}

/// Picks the build location for [requested] on a server with [platform].
BuildDecision decideBuild({
  required BuildLocation requested,
  required HostTools host,
  required DockerPlatform platform,
}) {
  BuildDecision remote(String why) => BuildDecision(
    BuildLocation.remote,
    'the server builds the images: $why',
    platform: platform,
  );
  if (requested == BuildLocation.remote) {
    return remote('build.location is remote');
  }
  if (platform.os != 'linux') {
    return remote('the server runs $platform containers, not Linux');
  }
  if (!host.docker) {
    return remote('Docker does not answer on this machine');
  }
  if (!host.buildx) {
    return remote(
      'docker buildx is not on this machine (brew install docker-buildx, '
      'or the buildx plugin of your Docker)',
    );
  }
  final same = host.os == platform.os && host.arch == platform.arch;
  if (requested != BuildLocation.localDocker && host.canCompileFor(platform)) {
    return BuildDecision(
      BuildLocation.local,
      same
          ? 'this machine is $platform: the server is compiled here'
          : 'Dart ${host.dartVersion} cross-compiles for $platform here '
                '(this machine is ${host.os}/${host.arch})',
      platform: platform,
      cross: !same,
    );
  }
  final why = requested == BuildLocation.localDocker
      ? 'build.location is local-docker'
      : host.dartVersion == null
      ? 'no dart on this machine'
      : 'Dart ${host.dartVersion} cannot compile for $platform';
  final emulated =
      host.dockerPlatform != null && host.dockerPlatform != platform;
  return BuildDecision(
    BuildLocation.localDocker,
    'Docker on this machine builds for $platform ($why)'
    '${emulated ? '; RUN steps of $platform run emulated' : ''}',
    platform: platform,
  );
}

/// Asks the server of [env] about its Docker.
Future<ServerDocker> probeServer(Ctx ctx, EnvConfig env) async =>
    ServerDocker.parse(await ctx.query(env, serverProbeScript));

/// Looks at the tools on this machine.
Future<HostTools> probeHost() async {
  Future<ProcessResult?> run(String exe, List<String> args) async {
    try {
      return await Process.run(exe, args);
    } on ProcessException {
      return null;
    }
  }

  final dart = await run('dart', ['--version']);
  final dv = dart == null
      ? null
      : RegExp(
          r'(\d+\.\d+\.\d+)',
        ).firstMatch('${dart.stdout}${dart.stderr}')?[1];
  final docker = await run('docker', [
    'version',
    '--format',
    '{{.Server.Os}}/{{.Server.Arch}}',
  ]);
  final buildx = await run('docker', ['buildx', 'version']);
  final uname = await run('uname', ['-m']);
  return HostTools(
    os: Platform.operatingSystem,
    arch: normalizeArch('${uname?.stdout ?? ''}') ?? 'arm64',
    dartVersion: dv,
    docker: docker != null && docker.exitCode == 0,
    buildx: buildx != null && buildx.exitCode == 0,
    dockerPlatform: docker != null && docker.exitCode == 0
        ? DockerPlatform.parse('${docker.stdout}')
        : null,
  );
}
