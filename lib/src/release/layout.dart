// Where things live on the server, and the files podship writes into each
// release.
//
//   <dir>/releases/<id>/          the files of one release
//   <dir>/releases/<id>/.podship/ release.json, compose-files, override.yml,
//                                 images, status, compose.sh
//   <dir>/current -> releases/<id>
//   <dir>/.podship/upload/        the rsync target; each release is a
//                                 hardlinked copy of it
//   <dir>/.podship/history.log    one line per deploy, rollback or promote
//   <dir>/<secrets.env_file>      .env (secrets, never shipped)
//   <dir>/<secrets.passwords_file>  passwords.yaml (never shipped)

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';
import '../remote/ssh.dart';

/// The paths of one environment on its server.
class EnvLayout {
  EnvLayout(this.env);
  final EnvConfig env;

  String get dir => env.dir;
  String get releases => '$dir/releases';
  String get current => '$dir/current';
  String get state => '$dir/.podship';
  String get upload => '$state/upload';
  String get history => '$state/history.log';
  String release(String id) => '$releases/$id';
  String composeSh(String id) => '${release(id)}/.podship/compose.sh';
  String get currentComposeSh => '$current/.podship/compose.sh';
  String get envFile => p.posix.join(dir, env.secrets.envFile);
  String get passwordsFile => p.posix.join(dir, env.secrets.passwordsFile);
}

/// The name of the image podship builds for [service] in [release].
String imageName(String composeProject, String service, String release) =>
    '$composeProject-$service:$release';

/// Services that have a `build:` key in any of the compose files.
List<String> builtServices(List<String> composeYamlTexts) {
  final out = <String>{};
  for (final text in composeYamlTexts) {
    final doc = loadYaml(text);
    if (doc is! YamlMap) continue;
    final services = doc['services'];
    if (services is! YamlMap) continue;
    for (final e in services.entries) {
      if (e.value is YamlMap && (e.value as YamlMap).containsKey('build')) {
        out.add('${e.key}');
      }
    }
  }
  return out.toList()..sort();
}

/// All service names in the compose files.
List<String> allServices(List<String> composeYamlTexts) {
  final out = <String>{};
  for (final text in composeYamlTexts) {
    final doc = loadYaml(text);
    if (doc is YamlMap && doc['services'] is YamlMap) {
      out.addAll((doc['services'] as YamlMap).keys.map((k) => '$k'));
    }
  }
  return out.toList()..sort();
}

/// The compose override podship writes for a release. It pins every built
/// service to an image tagged with the release id, so environments never
/// overwrite each other's images, and old releases keep their images.
String overrideYaml({
  required String composeProject,
  required String release,
  required List<String> built,
  Map<String, String> buildContexts = const {},
  Map<String, String> pinnedImages = const {},
  String? sharedNetwork,
  String? serverService,
}) {
  final b = StringBuffer()
    ..writeln('# Written by podship for release $release. Do not edit.')
    ..writeln('services:');
  final names = {...built, ...pinnedImages.keys}.toList()..sort();
  if (sharedNetwork != null && serverService != null) {
    names.add(serverService);
  }
  for (final s in {...names}) {
    b.writeln('  $s:');
    if (built.contains(s) || pinnedImages.containsKey(s)) {
      b.writeln(
        '    image: ${jsonEncode(pinnedImages[s] ?? imageName(composeProject, s, release))}',
      );
    }
    final ctx = buildContexts[s];
    if (ctx != null && (built.contains(s) || pinnedImages.containsKey(s))) {
      b
        ..writeln('    build:')
        ..writeln('      context: ${jsonEncode(ctx)}');
    }
    if (sharedNetwork != null && s == serverService) {
      b
        ..writeln('    networks:')
        ..writeln('      - default')
        ..writeln('      - ${jsonEncode(sharedNetwork)}');
    }
  }
  if (sharedNetwork != null) {
    b
      ..writeln('networks:')
      ..writeln('  default: {}')
      ..writeln('  ${jsonEncode(sharedNetwork)}:')
      ..writeln('    external: true');
  }
  return b.toString();
}

/// The `compose.sh` wrapper of a release. It runs docker compose with the
/// right project, files and ports, so anyone can do
/// `<dir>/current/.podship/compose.sh ps` on the server.
String composeSh({
  required String composeProject,
  required String releaseDir,
  required List<String> composeFiles,
  Map<String, int> ports = const {},
  String? remotePath,
}) {
  final files = [
    for (final f in composeFiles) '-f ${shq(p.posix.join(releaseDir, f))}',
    '-f ${shq('$releaseDir/.podship/override.yml')}',
  ].join(' ');
  final b = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('# Written by podship. Runs docker compose for this release.')
    ..writeln('set -euo pipefail');
  if (remotePath != null) b.writeln('export PATH=${shq(remotePath)}:"\$PATH"');
  for (final e in ports.entries) {
    b.writeln('export PODSHIP_PORT_${_envName(e.key)}=${e.value}');
  }
  b.writeln(
    'exec docker compose -p ${shq(composeProject)} '
    '--project-directory ${shq(releaseDir)} '
    '--env-file ${shq('$releaseDir/.env')} $files "\$@"',
  );
  return b.toString();
}

String _envName(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');

/// The metadata of a release, stored as `.podship/release.json`.
class ReleaseMeta {
  ReleaseMeta({
    required this.id,
    required this.sha,
    required this.ref,
    required this.dirty,
    required this.createdAt,
    required this.createdBy,
    required this.images,
    this.promotedFrom,
  });

  factory ReleaseMeta.fromJson(Map<String, Object?> j) => ReleaseMeta(
    id: j['id'] as String,
    sha: j['sha'] as String? ?? '',
    ref: j['ref'] as String? ?? '',
    dirty: j['dirty'] as bool? ?? false,
    createdAt: j['created_at'] as String? ?? '',
    createdBy: j['created_by'] as String? ?? '',
    images: [for (final i in (j['images'] as List? ?? const [])) '$i'],
    promotedFrom: j['promoted_from'] as String?,
  );

  final String id;
  final String sha;
  final String ref;
  final bool dirty;
  final String createdAt;
  final String createdBy;
  final List<String> images;
  final String? promotedFrom;

  Map<String, Object?> toJson() => {
    'id': id,
    'sha': sha,
    'ref': ref,
    'dirty': dirty,
    'created_at': createdAt,
    'created_by': createdBy,
    'images': images,
    if (promotedFrom != null) 'promoted_from': promotedFrom,
  };
}
