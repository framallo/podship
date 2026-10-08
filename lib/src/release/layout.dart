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

/// The `ports:` entries of [service] in the compose files (last wins).
List<String> servicePorts(List<String> composeYamlTexts, String service) {
  var out = <String>[];
  for (final text in composeYamlTexts) {
    final doc = loadYaml(text);
    if (doc is! YamlMap || doc['services'] is! YamlMap) continue;
    final svc = (doc['services'] as YamlMap)[service];
    if (svc is YamlMap && svc['ports'] is YamlList) {
      out = [for (final p in svc['ports'] as YamlList) '$p'];
    }
  }
  return out;
}

/// The container port of a compose `ports:` entry like
/// `127.0.0.1:${PORT:-8082}:8082`.
int? containerPort(String entry) {
  final last = entry.split(':').last.split('/').first;
  return int.tryParse(last);
}

/// The nginx config of the load balancer in front of server replicas.
/// `ip_hash` keeps a client on one container, which streams need.
String lbConfig(List<int> ports, {String server = 'server'}) {
  final b = StringBuffer(
    '# Written by podship: load balancer for $server replicas.\n',
  );
  b.writeln(
    'map \$http_upgrade \$connection_upgrade { default upgrade; "" close; }',
  );
  for (final port in ports) {
    b
      ..writeln(
        'upstream p$port { ip_hash; server $server:$port; server $server-replica:$port; }',
      )
      ..writeln('server {')
      ..writeln('  listen $port;')
      ..writeln('  client_max_body_size 64m;')
      ..writeln('  location / {')
      ..writeln('    proxy_pass http://p$port;')
      ..writeln('    proxy_http_version 1.1;')
      ..writeln('    proxy_set_header Host \$host;')
      ..writeln(
        '    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;',
      )
      ..writeln('    proxy_set_header Upgrade \$http_upgrade;')
      ..writeln('    proxy_set_header Connection \$connection_upgrade;')
      ..writeln('    proxy_read_timeout 3600s;')
      ..writeln('  }')
      ..writeln('}');
  }
  return b.toString();
}

/// Serverpod settings for the override: environment, replicas, Redis,
/// graceful stop, egress.
class OverrideExtras {
  OverrideExtras({
    this.serverEnv = const {},
    this.stopGraceSeconds,
    this.replicas = 1,
    this.redis = false,
    this.serverPorts = const [],
    this.extendsFile,
    this.replicaEntrypoint,
    this.egressProxy,
    this.egressServices = const [],
    this.noProxy = const [],
  });
  final Map<String, String> serverEnv;
  final int? stopGraceSeconds;
  final int replicas;
  final bool redis;
  final List<String> serverPorts;

  /// The compose file that defines the server service, for `extends`.
  final String? extendsFile;
  final List<String>? replicaEntrypoint;
  final String? egressProxy;
  final List<String> egressServices;
  final List<String> noProxy;
}

/// A YAML value that compose reads as "replace the list" (`!reset []`).
class _Reset {
  const _Reset();
}

const _reset = _Reset();

/// Writes [value] as YAML: maps as blocks, everything else as JSON (which
/// is valid YAML).
void _yaml(StringBuffer b, Object? value, int indent) {
  final pad = '  ' * indent;
  if (value is Map) {
    for (final e in value.entries) {
      final v = e.value;
      if (v is Map && v.isNotEmpty) {
        b.writeln('$pad${jsonEncode('${e.key}')}:');
        _yaml(b, v, indent + 1);
      } else if (v is _Reset) {
        b.writeln('$pad${jsonEncode('${e.key}')}: !reset []');
      } else {
        b.writeln(
          '$pad${jsonEncode('${e.key}')}: ${jsonEncode(v is Map ? {} : v)}',
        );
      }
    }
  }
}

/// The compose override podship writes for a release. It pins every built
/// service to an image tagged with the release id, so environments never
/// overwrite each other's images, and old releases keep their images. It
/// also carries the Serverpod settings, replicas, Redis and egress.
String overrideYaml({
  required String composeProject,
  required String release,
  required List<String> built,
  Map<String, String> buildContexts = const {},
  Map<String, String> pinnedImages = const {},
  String? sharedNetwork,
  String? serverService,
  OverrideExtras? extras,
}) {
  final services = <String, Map<String, Object?>>{};
  Map<String, Object?> svc(String name) => services.putIfAbsent(name, () => {});
  final server = serverService ?? 'server';
  for (final s in {...built, ...pinnedImages.keys}) {
    svc(s)['image'] = pinnedImages[s] ?? imageName(composeProject, s, release);
    final ctx = buildContexts[s];
    if (ctx != null) svc(s)['build'] = {'context': ctx};
  }
  if (sharedNetwork != null) {
    svc(server)['networks'] = ['default', sharedNetwork];
  }
  final x = extras;
  if (x != null) {
    final lb = x.replicas > 1;
    if (x.serverEnv.isNotEmpty) {
      svc(server)['environment'] = {...x.serverEnv};
    }
    if (x.stopGraceSeconds != null) {
      svc(server)['stop_grace_period'] = '${x.stopGraceSeconds}s';
    }
    if (lb) {
      svc(server)['ports'] = _reset;
      services['$server-replica'] = {
        'extends': {'file': x.extendsFile, 'service': server},
        'ports': _reset,
        'deploy': {'replicas': x.replicas - 1},
        'environment': {...x.serverEnv, 'SERVERPOD_SERVER_ROLE': 'serverless'},
        if (x.replicaEntrypoint != null) 'entrypoint': x.replicaEntrypoint,
        if (x.stopGraceSeconds != null)
          'stop_grace_period': '${x.stopGraceSeconds}s',
        if (pinnedImages[server] != null || built.contains(server))
          'image':
              pinnedImages[server] ??
              imageName(composeProject, server, release),
        if (sharedNetwork != null) 'networks': ['default', sharedNetwork],
      };
      services['podship-lb'] = {
        'image': 'nginx:1.27-alpine',
        'restart': 'unless-stopped',
        'volumes': ['./.podship/lb.conf:/etc/nginx/conf.d/default.conf:ro'],
        'depends_on': [server, '$server-replica'],
        'ports': x.serverPorts,
      };
    }
    if (x.redis || lb) {
      services['redis'] = {
        'image': 'redis:7-alpine',
        'restart': 'unless-stopped',
        'command': ['redis-server', '--save', '', '--appendonly', 'no'],
      };
    }
    if (x.egressProxy != null) {
      for (final s in x.egressServices) {
        final env = (svc(s)['environment'] as Map<String, Object?>?) ?? {};
        env.addAll({
          'HTTPS_PROXY': x.egressProxy,
          'HTTP_PROXY': x.egressProxy,
          'ALL_PROXY': x.egressProxy,
          'NO_PROXY': x.noProxy.join(','),
          if (s == 'chrome') 'PODSHIP_CHROME_PROXY': x.egressProxy,
        });
        svc(s)['environment'] = env;
      }
    }
  }
  final b = StringBuffer()
    ..writeln('# Written by podship for release $release. Do not edit.')
    ..writeln('services:');
  final names = services.keys.toList()..sort();
  for (final n in names) {
    b.writeln('  ${jsonEncode(n)}:');
    _yaml(b, services[n], 2);
  }
  if (services.isEmpty) b.writeln('  {}');
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
  String? blueGreenState,
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
  if (blueGreenState != null) {
    // Blue/green: the project is the active color unless the caller names
    // one; the color's override (no host ports, the front network) comes
    // last.
    b
      ..writeln(
        'proj="\${PODSHIP_COMPOSE_PROJECT:-\$(cat ${shq('$blueGreenState/active-project')} 2>/dev/null || echo ${shq(composeProject)})}"',
      )
      ..writeln('bg=()')
      ..writeln(
        '[ -f ${shq('$releaseDir/.podship/')}"bg-\$proj.yml" ] && bg=(-f ${shq('$releaseDir/.podship/')}"bg-\$proj.yml")',
      )
      ..writeln(
        'exec docker compose -p "\$proj" '
        '--project-directory ${shq(releaseDir)} '
        '--env-file ${shq('$releaseDir/.env')} $files \${bg[@]+"\${bg[@]}"} "\$@"',
      );
    return b.toString();
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
    this.web = const {},
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
    web: {
      for (final e in ((j['web'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
  );

  final String id;
  final String sha;
  final String ref;
  final bool dirty;
  final String createdAt;
  final String createdBy;
  final List<String> images;
  final String? promotedFrom;

  /// The input hash of each Flutter web app build in this release, by app
  /// name. A later release with the same hash takes the build instead of
  /// building again.
  final Map<String, String> web;

  Map<String, Object?> toJson() => {
    'id': id,
    'sha': sha,
    'ref': ref,
    'dirty': dirty,
    'created_at': createdAt,
    'created_by': createdBy,
    'images': images,
    if (promotedFrom != null) 'promoted_from': promotedFrom,
    if (web.isNotEmpty) 'web': web,
  };
}
