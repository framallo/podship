// The runtime image of a Serverpod server compiled on this machine.
//
// A Serverpod Dockerfile has a build stage (the Dart SDK compiles the
// server) and a small final stage (alpine, the Dart runtime files, the
// executable, config, migrations and web). In `local` mode podship
// compiles the server itself, so it keeps the project's final stage and
// replaces each `COPY --from=<build stage>` with a copy of the same files
// from this machine:
//
//   /runtime/                      → COPY --from=<the build stage's image>
//   …/build/bundle/…               → the bundle that `dart build cli` wrote
//   any path the build stage COPYed from the context → the same context path
//
// The final stage's FROM, ENV, WORKDIR, EXPOSE, RUN, USER and ENTRYPOINT
// stay as the project wrote them.

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A Dockerfile that podship cannot turn into a runtime image.
class DockerfileException implements Exception {
  DockerfileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One instruction (continuation lines joined).
class _Instr {
  _Instr(this.keyword, this.args, this.text);
  final String keyword;
  final String args;
  final String text;
}

List<_Instr> _instructions(String text) {
  final out = <_Instr>[];
  final buf = StringBuffer();
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (buf.isEmpty && (line.trim().isEmpty || line.trim().startsWith('#'))) {
      continue;
    }
    if (line.endsWith('\\')) {
      buf.write('${line.substring(0, line.length - 1)} ');
      continue;
    }
    buf.write(line);
    final s = buf.toString().trim();
    buf.clear();
    final m = RegExp(r'^(\S+)\s*(.*)$', dotAll: true).firstMatch(s);
    if (m == null) continue;
    out.add(_Instr(m[1]!.toUpperCase(), m[2]!.trim(), s));
  }
  if (buf.isNotEmpty) {
    final s = buf.toString().trim();
    final m = RegExp(r'^(\S+)\s*(.*)$', dotAll: true).firstMatch(s);
    if (m != null) out.add(_Instr(m[1]!.toUpperCase(), m[2]!.trim(), s));
  }
  return out;
}

class _Stage {
  _Stage(this.image, this.name);
  final String image;
  final String? name;
  final List<_Instr> body = [];
}

List<_Stage> _stages(String text) {
  final stages = <_Stage>[];
  for (final i in _instructions(text)) {
    if (i.keyword == 'FROM') {
      final parts = i.args
          .split(RegExp(r'\s+'))
          .where((x) => !x.startsWith('--'))
          .toList();
      final as = parts.length >= 3 && parts[1].toLowerCase() == 'as'
          ? parts[2]
          : null;
      stages.add(_Stage(parts.first, as));
    } else if (stages.isNotEmpty) {
      stages.last.body.add(i);
    }
  }
  return stages;
}

/// Splits `COPY` arguments into flags, sources and the destination.
({List<String> flags, List<String> srcs, String dst}) _copyArgs(String args) {
  final words = args.split(RegExp(r'\s+'));
  final flags = [
    for (final w in words)
      if (w.startsWith('--')) w,
  ];
  final rest = [
    for (final w in words)
      if (!w.startsWith('--')) w,
  ];
  if (rest.length < 2) throw DockerfileException('COPY $args: no destination');
  return (flags: flags, srcs: rest.sublist(0, rest.length - 1), dst: rest.last);
}

/// What [runtimeDockerfile] made, and what it needs on disk.
class RuntimeDockerfile {
  RuntimeDockerfile(
    this.text, {
    required this.builderImage,
    required this.renames,
    required this.hasRun,
  });

  /// The new Dockerfile (its context is the project root).
  final String text;

  /// The image of the build stage, like `dart:3.12.2`. Its `/runtime/`
  /// goes into the image; the SDK does not.
  final String builderImage;

  /// Renames the build stage did inside the bundle, like
  /// `bin/main` → `bin/server`.
  final Map<String, String> renames;

  /// Whether the final stage has RUN steps (they need emulation when the
  /// server's CPU differs from this machine's).
  final bool hasRun;
}

/// Turns the project's [dockerfile] into one that takes the compiled
/// bundle from [bundleDir] (relative to the build context) instead of
/// compiling. With [jitKernel], the bundle holds `bin/server.dill` and the
/// image gets the Dart VM from the build stage's image.
RuntimeDockerfile runtimeDockerfile(
  String dockerfile, {
  required String bundleDir,
  bool jitKernel = false,
}) {
  final stages = _stages(dockerfile);
  if (stages.length < 2) {
    throw DockerfileException(
      'the Dockerfile has one stage: podship needs a build stage and a '
      'runtime stage to replace the build',
    );
  }
  final last = stages.last;
  final builders = {
    for (final (i, s) in stages.indexed.take(stages.length - 1)) ...{
      '$i': s,
      ?s.name: s,
    },
  };
  // Map the build stage's absolute paths back to context paths.
  final renames = <String, String>{};
  final copied = <String, ({String stage, String ctx})>{};
  for (final s in stages.take(stages.length - 1)) {
    var workdir = '/';
    for (final i in s.body) {
      if (i.keyword == 'WORKDIR') {
        workdir = p.posix.normalize(p.posix.join(workdir, i.args.trim()));
      } else if (i.keyword == 'COPY' || i.keyword == 'ADD') {
        final a = _copyArgs(i.args);
        if (a.flags.any((f) => f.startsWith('--from'))) continue;
        for (final src in a.srcs) {
          var dst = p.posix.normalize(p.posix.join(workdir, a.dst));
          // Into a folder: a file keeps its name; a folder's contents go
          // into the folder (a dot in the name marks a file).
          if (a.dst.endsWith('/') || a.dst == '.' || a.srcs.length > 1) {
            if (src != '.' &&
                !src.endsWith('/') &&
                p.posix.basename(src).contains('.')) {
              dst = p.posix.join(dst, p.posix.basename(src));
            }
          }
          copied[dst] = (stage: s.name ?? '', ctx: _clean(src));
        }
      } else if (i.keyword == 'RUN') {
        for (final m in RegExp(
          r'mv\s+(\S*build/bundle/)(\S+)\s+(\S*build/bundle/)(\S+)',
        ).allMatches(i.args)) {
          renames[m[2]!] = m[4]!;
        }
      }
    }
  }
  String? builderImage;
  var hasRun = false;
  final b = StringBuffer(
    '# Written by podship from the project Dockerfile: the build stage is\n'
    '# replaced by files compiled on the podship machine.\n',
  );
  b.writeln('FROM ${last.image}');
  for (final i in last.body) {
    if (i.keyword == 'RUN') hasRun = true;
    if (i.keyword != 'COPY') {
      b.writeln(i.text);
      continue;
    }
    final a = _copyArgs(i.args);
    final from = a.flags
        .where((f) => f.startsWith('--from='))
        .map((f) => f.substring('--from='.length))
        .firstOrNull;
    final stage = from == null ? null : builders[from];
    if (stage == null) {
      b.writeln(i.text);
      continue;
    }
    builderImage ??= stage.image;
    final flags = a.flags.where((f) => !f.startsWith('--from=')).join(' ');
    final pre = flags.isEmpty ? 'COPY ' : 'COPY $flags ';
    for (final src in a.srcs) {
      final abs = p.posix.normalize(src);
      final slash = src.endsWith('/') ? '/' : '';
      if (abs == '/runtime' || abs.startsWith('/runtime/')) {
        b.writeln(
          'COPY ${flags.isEmpty ? '' : '$flags '}--from=${stage.image} $src ${a.dst}',
        );
        continue;
      }
      final bi = abs.indexOf('/build/bundle');
      if (bi >= 0) {
        final rest = abs.substring(bi + '/build/bundle'.length);
        final local = p.posix.join(
          bundleDir,
          rest.startsWith('/') ? rest.substring(1) : rest,
        );
        b.writeln('$pre${p.posix.normalize(local)}$slash ${a.dst}');
        if (jitKernel && rest.isEmpty) {
          b.writeln(
            'COPY --from=${stage.image} /usr/lib/dart/bin/dart /usr/lib/dart/bin/dart',
          );
        }
        continue;
      }
      final ctx = _contextPath(abs, copied);
      if (ctx == null) {
        throw DockerfileException(
          'COPY --from=$from $src: podship cannot tell where $src comes '
          'from on this machine; use build.location: local-docker',
        );
      }
      b.writeln('$pre$ctx$slash ${a.dst}');
    }
  }
  if (builderImage == null) {
    throw DockerfileException(
      'the last stage copies nothing from a build stage',
    );
  }
  return RuntimeDockerfile(
    b.toString(),
    builderImage: builderImage,
    renames: renames,
    hasRun: hasRun,
  );
}

String _clean(String src) {
  final s = p.posix.normalize(src);
  return s == '.' ? '' : s;
}

String? _contextPath(
  String abs,
  Map<String, ({String stage, String ctx})> copied,
) {
  String? best;
  for (final dst in copied.keys) {
    if (abs == dst || abs.startsWith('$dst/')) {
      if (best == null || dst.length > best.length) best = dst;
    }
  }
  if (best == null) return null;
  final rest = abs.substring(best.length);
  final ctx = copied[best]!.ctx;
  final joined = rest.isEmpty
      ? ctx
      : p.posix.join(ctx, rest.startsWith('/') ? rest.substring(1) : rest);
  return joined.isEmpty ? '.' : joined;
}

/// The `build:` of one compose service.
class ServiceBuild {
  ServiceBuild({
    required this.service,
    required this.context,
    this.dockerfile,
    this.args = const {},
    this.target,
    this.platform,
  });

  final String service;

  /// The context, relative to the project root (or absolute).
  final String context;

  /// The Dockerfile, relative to [context].
  final String? dockerfile;
  final Map<String, String> args;
  final String? target;

  /// The service's `platform:`, like `linux/amd64`.
  final String? platform;

  /// The Dockerfile path relative to the project root.
  String get dockerfilePath =>
      p.posix.normalize(p.posix.join(context, dockerfile ?? 'Dockerfile'));
}

/// The `build:` sections of the compose files (later files win).
Map<String, ServiceBuild> serviceBuilds(List<String> composeYamlTexts) {
  final raw = <String, Map<String, Object?>>{};
  for (final text in composeYamlTexts) {
    final doc = loadYaml(text);
    if (doc is! YamlMap || doc['services'] is! YamlMap) continue;
    for (final e in (doc['services'] as YamlMap).entries) {
      if (e.value is! YamlMap) continue;
      final svc = e.value as YamlMap;
      final m = raw.putIfAbsent('${e.key}', () => {});
      if (svc['platform'] != null) m['platform'] = '${svc['platform']}';
      final b = svc['build'];
      if (b is String) {
        m['context'] = b;
      } else if (b is YamlMap) {
        for (final k in ['context', 'dockerfile', 'target']) {
          if (b[k] != null) m[k] = '${b[k]}';
        }
        final args = b['args'];
        if (args is YamlMap) {
          m['args'] = {
            ...((m['args'] as Map<String, String>?) ?? {}),
            for (final a in args.entries) '${a.key}': '${a.value}',
          };
        } else if (args is YamlList) {
          final out = <String, String>{};
          for (final a in args) {
            final s = '$a', i = s.indexOf('=');
            if (i > 0) out[s.substring(0, i)] = s.substring(i + 1);
          }
          m['args'] = out;
        }
      }
    }
  }
  return {
    for (final e in raw.entries)
      if (e.value['context'] != null)
        e.key: ServiceBuild(
          service: e.key,
          context: e.value['context'] as String,
          dockerfile: e.value['dockerfile'] as String?,
          args: (e.value['args'] as Map<String, String>?) ?? const {},
          target: e.value['target'] as String?,
          platform: e.value['platform'] as String?,
        ),
  };
}
