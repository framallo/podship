// Reads the state of an environment from its server (read only).

import 'dart:convert';

import '../config/config.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../server/registry.dart';
import 'context.dart';

/// One release on the server.
class ReleaseInfo {
  ReleaseInfo(this.id, this.status, this.meta);
  final String id;

  /// ok, failed, pending or adopted.
  final String status;
  final ReleaseMeta? meta;
}

/// The state of an environment.
class EnvState {
  EnvState({
    required this.current,
    required this.releases,
    required this.registryText,
    required this.listening,
    required this.envFileExists,
    required this.passwordsFileExists,
    required this.dbRunning,
  });

  final String? current;
  final List<ReleaseInfo> releases;
  final String registryText;
  final Set<int> listening;
  final bool envFileExists;
  final bool passwordsFileExists;
  final bool dbRunning;

  Registry get registry => Registry.parse(registryText);
  List<String> get ids => [for (final r in releases) r.id];
  Set<String> get failed => {
    for (final r in releases)
      if (r.status == 'failed') r.id,
  };

  /// An empty state, for a server that is not reachable in `--dry-run`.
  static EnvState empty() => EnvState(
    current: null,
    releases: const [],
    registryText: '',
    listening: const {},
    envFileExists: false,
    passwordsFileExists: false,
    dbRunning: false,
  );
}

/// The script that prints the state. Its output is parsed by [parseState].
String stateScript(EnvConfig env) {
  final l = EnvLayout(env);
  final dbFilter = env.database.mode == DatabaseMode.shared
      ? '--filter name=^${DatabaseConfig.sharedContainer}\$'
      : '--filter label=com.docker.compose.project=${env.composeProject} '
            '--filter label=com.docker.compose.service=${env.database.service}';
  return '''
cur=\$(readlink ${shq(l.current)} 2>/dev/null || true)
echo "CURRENT \${cur##*/}"
if [ -d ${shq(l.releases)} ]; then
  for d in ${shq(l.releases)}/*/; do
    [ -d "\$d" ] || continue
    id=\$(basename "\$d")
    st=\$(cat "\$d/.podship/status" 2>/dev/null || echo unknown)
    meta=\$(tr -d '\\n' < "\$d/.podship/release.json" 2>/dev/null || echo '{}')
    echo "R \$id \$st \$meta"
  done
fi
[ -f ${shq(l.envFile)} ] && echo "ENVFILE yes"
[ -f ${shq(l.passwordsFile)} ] && echo "PASSWORDS yes"
if command -v docker >/dev/null && [ -n "\$(docker ps -q $dbFilter 2>/dev/null)" ]; then echo "DB yes"; fi
if command -v ss >/dev/null; then
  ss -Hltn 2>/dev/null | awk '{print \$4}' | sed 's/.*://' | sort -un | tr '\\n' ' ' | sed 's/^/PORTS /'; echo
elif command -v netstat >/dev/null; then
  netstat -an -p tcp 2>/dev/null | awk '/LISTEN/ {print \$4}' | sed 's/.*[.:]//' | sort -un | tr '\\n' ' ' | sed 's/^/PORTS /'; echo
fi
echo "REGISTRY-BEGIN"
cat ${shq(env.registryPath)} 2>/dev/null || true
echo "REGISTRY-END"
''';
}

EnvState parseState(String out) {
  String? current;
  final releases = <ReleaseInfo>[];
  final reg = StringBuffer();
  var inReg = false;
  var envFile = false, passwords = false, db = false;
  final listening = <int>{};
  for (final line in const LineSplitter().convert(out)) {
    if (inReg) {
      if (line == 'REGISTRY-END') {
        inReg = false;
      } else {
        reg.writeln(line);
      }
      continue;
    }
    if (line == 'REGISTRY-BEGIN') {
      inReg = true;
    } else if (line.startsWith('CURRENT ')) {
      final c = line.substring(8).trim();
      current = c.isEmpty ? null : c;
    } else if (line.startsWith('R ')) {
      final parts = line.split(' ');
      final metaText = parts.skip(3).join(' ');
      ReleaseMeta? meta;
      try {
        final j = jsonDecode(metaText);
        if (j is Map<String, Object?> && j['id'] != null) {
          meta = ReleaseMeta.fromJson(j);
        }
      } catch (_) {}
      releases.add(ReleaseInfo(parts[1], parts[2], meta));
    } else if (line == 'ENVFILE yes') {
      envFile = true;
    } else if (line == 'PASSWORDS yes') {
      passwords = true;
    } else if (line == 'DB yes') {
      db = true;
    } else if (line.startsWith('PORTS ')) {
      for (final p in line.substring(6).split(' ')) {
        final n = int.tryParse(p);
        if (n != null) listening.add(n);
      }
    }
  }
  releases.sort((a, b) => a.id.compareTo(b.id));
  return EnvState(
    current: current,
    releases: releases,
    registryText: reg.toString(),
    listening: listening,
    envFileExists: envFile,
    passwordsFileExists: passwords,
    dbRunning: db,
  );
}

/// Fetches the state. In `--dry-run`, an unreachable server gives an
/// empty state and a warning instead of an error.
Future<EnvState> fetchState(Ctx ctx, EnvConfig env) async {
  try {
    return parseState(await ctx.query(env, stateScript(env)));
  } on RemoteException catch (e) {
    if (!ctx.dryRun) rethrow;
    ctx.log.warn('cannot read ${env.host} ($e); planning with an empty state');
    return EnvState.empty();
  }
}
