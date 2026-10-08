// Input hashes: "did the sources of this build or test suite change?"
//
// A Flutter web build or a test suite is skipped when its inputs are the
// same as in a release that was built, or a run that passed, before. The
// inputs of a package are its folder, the folders of its `path:`
// dependencies, and the nearest `pubspec.lock`. The hash comes from git
// tree ids (`git rev-parse <sha>:<path>`), so it is deterministic, costs no
// file walk, and only exists for a commit: a worktree build is never
// skipped.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The git object id of [path] in commit [sha], or null when the path is
/// not in the commit.
Future<String?> gitObjectId(String root, String sha, String path) async {
  final r = await Process.run('git', [
    'rev-parse',
    '--verify',
    '-q',
    '$sha:$path',
  ], workingDirectory: root);
  if (r.exitCode != 0) return null;
  final out = (r.stdout as String).trim();
  return out.isEmpty ? null : out;
}

/// The `path:` dependencies of the pubspec at [pubspecText], as paths
/// relative to the project root. [pkgDir] is the package folder, relative
/// to the root. Paths that leave the root are dropped.
List<String> pathDependencies(String pubspecText, String pkgDir) {
  final Object? doc;
  try {
    doc = loadYaml(pubspecText);
  } catch (_) {
    return const [];
  }
  if (doc is! YamlMap) return const [];
  final out = <String>{};
  for (final section in const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    final deps = doc[section];
    if (deps is! YamlMap) continue;
    for (final v in deps.values) {
      if (v is YamlMap && v['path'] is String) {
        final rel = p.posix.normalize(
          p.posix.join(pkgDir, v['path'] as String),
        );
        if (rel == '.' || rel.startsWith('../')) continue;
        out.add(rel);
      }
    }
  }
  return out.toList()..sort();
}

/// The nearest `pubspec.lock` at or above [pkgDir] inside commit [sha], as
/// a path relative to the root, or null.
Future<String?> nearestLock(String root, String sha, String pkgDir) async {
  var dir = p.posix.normalize(pkgDir);
  while (true) {
    final lock = dir == '.' ? 'pubspec.lock' : '$dir/pubspec.lock';
    if (await gitObjectId(root, sha, lock) != null) return lock;
    if (dir == '.') return null;
    final parent = p.posix.dirname(dir);
    dir = parent == dir ? '.' : parent;
  }
}

/// The input paths of the package in [pkgDir] inside commit [sha]: the
/// folder, its path dependencies (read from its pubspec in the commit),
/// and the nearest lock file. [extra] paths are added.
Future<List<String>> packageInputs(
  String root,
  String sha,
  String pkgDir, {
  List<String> extra = const [],
}) async {
  final dir = p.posix.normalize(pkgDir);
  final paths = <String>{dir, ...extra};
  final pubspec = await Process.run('git', [
    'show',
    '$sha:$dir/pubspec.yaml',
  ], workingDirectory: root);
  if (pubspec.exitCode == 0) {
    paths.addAll(pathDependencies(pubspec.stdout as String, dir));
  }
  final lock = await nearestLock(root, sha, dir);
  if (lock != null) paths.add(lock);
  return paths.toList()..sort();
}

/// The hash of [paths] in commit [sha], plus [salt] (tool versions, flags).
/// Null when [sha] is not a commit or a path is not in it.
Future<String?> inputsHash(
  String root,
  String sha,
  List<String> paths, {
  List<String> salt = const [],
}) async {
  if (sha == 'nogit' || paths.isEmpty) return null;
  final parts = <String>[];
  for (final path in paths) {
    final id = await gitObjectId(root, sha, path);
    if (id == null) return null;
    parts.add('$path=$id');
  }
  parts.addAll(salt.map((s) => 'salt=$s'));
  return sha256.convert(utf8.encode(parts.join('\n'))).toString();
}

String? _flutterTag;

/// `flutter <version>+<engine>`, once per process, or null without
/// Flutter.
Future<String?> flutterVersionTag() async {
  if (_flutterTag != null) return _flutterTag!.isEmpty ? null : _flutterTag;
  try {
    final r = await Process.run('flutter', ['--version', '--machine']);
    if (r.exitCode == 0) {
      final j = jsonDecode(r.stdout as String) as Map;
      _flutterTag = 'flutter ${j['flutterVersion']}+${j['engineContentHash']}';
      return _flutterTag;
    }
  } catch (_) {}
  _flutterTag = '';
  return null;
}

String? _dartTag;

/// `dart <version>` of the `dart` on PATH (not this process's SDK, which
/// in a compiled podship is podship's own), once per process, or null.
Future<String?> dartVersionTag() async {
  if (_dartTag != null) return _dartTag!.isEmpty ? null : _dartTag;
  try {
    final r = await Process.run('dart', ['--version']);
    if (r.exitCode == 0) {
      final out = '${r.stdout}${r.stderr}'.trim();
      final m = RegExp(r'version: (\S+)').firstMatch(out);
      _dartTag = 'dart ${m?[1] ?? out}';
      return _dartTag;
    }
  } catch (_) {}
  _dartTag = '';
  return null;
}
