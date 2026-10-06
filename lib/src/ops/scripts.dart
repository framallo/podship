// Small bash snippets that podship runs on servers.
//
// They run with the server's bash, which is 3.2 on macOS, and with GNU or
// BSD tools. Keep them portable: no associative arrays, no `mv -T`, no
// `cp -l` without a fallback, no `sha256sum` without a fallback.

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../release/layout.dart';
import '../remote/assets.g.dart';
import '../remote/ssh.dart';
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

/// Installs the backup and restore scripts into the podship home.
String installAssets(EnvConfig env) => [
  for (final e in remoteAssets.entries)
    writeFile('${env.libDir}/${e.key}', e.value, mode: '755'),
].join();

/// Replaces the registry, but only if nobody changed it since podship read
/// [previous].
String writeRegistry(EnvConfig env, String previous, String next) {
  final prevB64 = base64.encode(utf8.encode(previous));
  final path = env.registryPath;
  return '''
mkdir -p ${shq(p.posix.dirname(path))}
now=\$(cat ${shq(path)} 2>/dev/null || true)
was=\$(echo ${shq(prevB64)} | base64 -d)
if [ "\$(printf '%s' "\$now" | _sha256)" != "\$(printf '%s' "\$was" | _sha256)" ]; then
  echo "the server registry changed while podship was planning; run the command again" >&2
  exit 1
fi
${writeFile(path, next)}''';
}

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
    ..writeln('# Read by ${env.libDir}/backup.sh and restore.sh. No secrets.');
  values.forEach((k, v) => s.writeln('$k=${shq(v)}'));
  return s.toString();
}

/// The path of the backup settings file.
String backupConfPath(EnvConfig env) =>
    '${env.etcDir}/${env.backup!.unit}.conf';

/// Takes a backup now: through the systemd unit when it exists, so a
/// scheduled and a manual backup run the same way; else the script itself.
String backupNow(EnvConfig env) {
  final b = env.backup!;
  return '''
if command -v systemctl >/dev/null 2>&1 && systemctl cat ${shq('${b.unit}.service')} >/dev/null 2>&1; then
  systemctl start ${shq('${b.unit}.service')} || { journalctl -u ${shq(b.unit)} -n 40 --no-pager -o cat; exit 1; }
  journalctl -u ${shq(b.unit)} -n 12 --no-pager -o cat
else
  ${shq('${env.libDir}/backup.sh')} ${shq(backupConfPath(env))}
fi
''';
}

/// The systemd units of a backup schedule.
({String service, String timer}) systemdUnits(
  PodshipConfig config,
  ResolvedEnv r,
) {
  final env = r.env;
  final b = env.backup!;
  final service =
      '''
# Written by podship: backup of ${config.project}/${env.name}.
# Run now: systemctl start ${b.unit}.service
# Log: journalctl -u ${b.unit}
[Unit]
Description=podship: backup of ${config.project}/${env.name}
Wants=docker.service
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=${env.dir}
Environment=HOME=/root
ExecStart=${env.libDir}/backup.sh ${backupConfPath(env)}
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=1h
''';
  final timer =
      '''
# Written by podship. Persistent: a missed run happens at boot.
[Unit]
Description=podship: daily backup of ${config.project}/${env.name}

[Timer]
OnCalendar=${r.backupSchedule}
Persistent=true
RandomizedDelaySec=2min

[Install]
WantedBy=timers.target
''';
  return (service: service, timer: timer);
}

/// Hour and minute of a daily `OnCalendar` value like `*-*-* 03:30:00 TZ`.
({int hour, int minute}) dailyTime(String onCalendar) {
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(onCalendar);
  if (m == null) {
    throw ConfigException('cannot read a daily time from "$onCalendar"');
  }
  return (hour: int.parse(m[1]!), minute: int.parse(m[2]!));
}

/// A launchd agent for macOS servers. launchd uses the Mac's own time zone.
String launchdPlist(
  PodshipConfig config,
  ResolvedEnv r, {
  required String path,
}) {
  final env = r.env;
  final t = dailyTime(r.backupSchedule!);
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by podship: daily backup of ${config.project}/${env.name}. -->
<plist version="1.0">
<dict>
  <key>Label</key><string>${env.backup!.unit}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${env.libDir}/backup.sh</string>
    <string>${backupConfPath(env)}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$path</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>${t.hour}</integer><key>Minute</key><integer>${t.minute}</integer></dict>
  <key>StandardOutPath</key><string>${env.podshipHome}/log/${env.backup!.unit}.log</string>
  <key>StandardErrorPath</key><string>${env.podshipHome}/log/${env.backup!.unit}.log</string>
</dict>
</plist>
''';
}
