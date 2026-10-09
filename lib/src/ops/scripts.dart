// Small bash snippets that podship runs on servers.
//
// They run with the server's bash, which is 3.2 on macOS, and with GNU or
// BSD tools. Keep them portable: no associative arrays, no `mv -T`, no
// `cp -l` without a fallback, no `sha256sum` without a fallback.

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../scheduler/agent.dart' show schedulerBin;
import 'resolve.dart';

/// Helper functions every remote script starts with.
const portableHelpers = r'''
_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
_mvlink() { mv -Tf "$1" "$2" 2>/dev/null || mv -hf "$1" "$2"; }
_cplink() { cp -al "$1" "$2" 2>/dev/null || { rm -rf "$2"; cp -ac "$1" "$2" 2>/dev/null; } || { rm -rf "$2"; cp -a "$1" "$2"; }; }
_os() { uname -s; }
''';

/// A heredoc that writes [content] to [path] atomically with [mode].
String writeFile(String path, String content, {String mode = '644'}) {
  var tag = 'PODSHIP_EOF';
  while (content.contains(tag)) {
    tag = '${tag}_X';
  }
  final body = content.endsWith('\n') ? content : '$content\n';
  return '''
mkdir -p ${shq(p.posix.dirname(path))}
cat > ${shq('$path.podship-tmp')} <<'$tag'
$body$tag
chmod $mode ${shq('$path.podship-tmp')}
mv -f ${shq('$path.podship-tmp')} ${shq(path)}
''';
}

/// A command of the podship binary on the server of [env]:
/// `<home>/bin/podship agent <sub> --conf <conf> <args>`.
String agentCommand(
  EnvConfig env,
  String sub, [
  List<String> args = const [],
]) =>
    '${shq(schedulerBin(env.podshipHome))} agent $sub --conf ${shq(backupConfPath(env))}'
    '${args.map((a) => ' ${shq(a)}').join()}\n';

/// One locked attempt to write the registry at [path]: exit 75 when the
/// file is no longer [previous] (the caller merges and tries again). A lock
/// older than 5 minutes is stale (a killed run) and is removed.
String writeRegistryLocked(String path, String previous, String next) {
  final prevB64 = base64.encode(utf8.encode(previous));
  final lock = '$path.lock';
  return '''
mkdir -p ${shq(p.posix.dirname(path))}
find ${shq(lock)} -maxdepth 0 -mmin +5 -exec rmdir {} \\; 2>/dev/null || true
i=0
until mkdir ${shq(lock)} 2>/dev/null; do
  i=\$((i + 1))
  if [ "\$i" -gt 120 ]; then echo "the registry lock is busy: $lock" >&2; exit 1; fi
  sleep 0.5
done
trap 'rmdir ${shq(lock)} 2>/dev/null || true' EXIT
now=\$(cat ${shq(path)} 2>/dev/null || true)
was=\$(echo ${shq(prevB64)} | base64 -d)
if [ "\$(printf '%s' "\$now" | _sha256)" != "\$(printf '%s' "\$was" | _sha256)" ]; then
  exit 75
fi
${writeFile(path, next)}''';
}

/// Prints the registry at [path] as one base64 line (empty when missing).
String readRegistryB64(String path) =>
    'if [ -f ${shq(path)} ]; then base64 < ${shq(path)} | tr -d \'\\n\'; fi; echo\n';

/// Brings release [id] up and points `current` at it.
String switchTo(
  EnvLayout l,
  String id, {
  required String action,
  String? from,
}) =>
    '''
cd ${shq(l.dir)}
${shq(l.composeSh(id))} up -d --no-build --remove-orphans
ln -sfn ${shq('releases/$id')} current.podship-new
_mvlink current.podship-new current
mkdir -p ${shq(l.state)}
echo "\$(date -u +%Y-%m-%dT%H:%M:%SZ) $action $id${from == null ? '' : ' from $from'} by \${SUDO_USER:-\$USER}" >> ${shq(l.history)}
''';

/// Sets the status file of release [id].
String setStatus(EnvLayout l, String id, String status) =>
    'echo $status > ${shq('${l.release(id)}/.podship/status')}\n';

/// Deletes releases and their images.
String prune(EnvLayout l, List<String> ids) {
  if (ids.isEmpty) return 'echo "nothing to prune"\n';
  final b = StringBuffer();
  for (final id in ids) {
    final dir = shq(l.release(id));
    b.writeln('if [ -d $dir ]; then');
    b.writeln(
      '  for img in \$(cat $dir/.podship/images 2>/dev/null); do docker image rm "\$img" >/dev/null 2>&1 || true; done',
    );
    b.writeln('  rm -rf -- $dir');
    b.writeln('  echo "pruned $id"');
    b.writeln('fi');
  }
  return b.toString();
}

/// Where the age recipients file of a backup lives on the server.
String recipientsPath(EnvConfig env) =>
    env.backup!.ageRecipientsRemote ??
    '${env.etcDir}/${env.backup!.unit}.recipients';

/// The settings file the backup and restore scripts read. No secrets.
String backupConf(PodshipConfig config, ResolvedEnv r, {bool encrypt = true}) {
  final env = r.env;
  final b = env.backup!;
  final l = EnvLayout(env);
  final shared = env.database.mode == DatabaseMode.shared;
  final values = <String, String>{
    'PROJECT': env.composeProject,
    'PROJECT_NAME': config.project,
    'DEST': b.dir,
    'LAYOUT_PLAIN': b.layout.plain,
    'LAYOUT_ENC': b.layout.encrypted,
    'DUMP_NAME': b.layout.dump,
    'COUNTS_NAME': b.layout.counts,
    'SECRETS_NAME': b.layout.secrets,
    'DB_SERVICE': env.database.service,
    'DB_NAME': env.database.name,
    'DB_USER': shared ? 'postgres' : env.database.user,
    'DB_CONTAINER': shared ? DatabaseConfig.sharedContainer : '',
    'TZ_LOCAL': b.timezone,
    'KEEP_DAYS': '${b.keepDays}',
    'KEEP_WEEKS': '${b.keepWeeks}',
    'KEEP_MONTHS': '${b.keepMonths}',
    'COMPRESS': b.compression,
    'VOLUMES': [
      for (final v in b.volumes)
        '${v.name}|${v.volume}|${v.sqlite.join(',')}|${v.files.join(',')}|${v.owner ?? ''}',
    ].join(' '),
    'SECRET_FILES': [
      '${l.envFile}|env',
      '${l.passwordsFile}|passwords.yaml',
    ].join(' '),
    'RECIPIENTS_FILE': encrypt ? recipientsPath(env) : '',
    'DRILL_TABLES': b.drillTables.join(' '),
    'DRILL_VOLATILE': b.drillVolatile.join(' '),
    'STOP_SERVICES': b.stopOnRestore.join(' '),
    'COMPOSE_SH': l.currentComposeSh,
    'HEALTH_URL': r.healthUrl,
    'BACKUP_UNIT': b.unit,
  };
  final s = StringBuffer()
    ..writeln('# Written by podship for ${config.project}/${env.name}.')
    ..writeln('# Read by podship agent backup, drill and restore. No secrets.');
  values.forEach((k, v) => s.writeln('$k=${shq(v)}'));
  return s.toString();
}

/// The path of the backup settings file.
String backupConfPath(EnvConfig env) =>
    '${env.etcDir}/${env.backup!.unit}.conf';

/// Takes a backup now: through the systemd unit when it exists (servers
/// set up before the scheduler), else with the podship binary.
String backupNow(EnvConfig env) {
  final b = env.backup!;
  return '''
if command -v systemctl >/dev/null 2>&1 && systemctl cat ${shq('${b.unit}.service')} >/dev/null 2>&1; then
  systemctl start ${shq('${b.unit}.service')} || { journalctl -u ${shq(b.unit)} -n 40 --no-pager -o cat; exit 1; }
  journalctl -u ${shq(b.unit)} -n 12 --no-pager -o cat
else
  ${agentCommand(env, 'backup').trim()}
fi
''';
}
