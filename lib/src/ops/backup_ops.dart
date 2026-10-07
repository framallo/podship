// backup: now, list, drill, restore, schedule, pull.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../plan/plan.dart';
import '../remote/ssh.dart';
import 'context.dart';
import 'deploy.dart';
import 'resolve.dart';
import 'scripts.dart';

/// Expands `~` in a local path.
String expandHome(String path) => path.startsWith('~/')
    ? p.join(Platform.environment['HOME'] ?? '', path.substring(2))
    : path;

/// Whether [s] looks like a public key rather than a file name.
bool isPublicKey(String s) =>
    s.startsWith('ssh-') || s.startsWith('ecdsa-') || s.startsWith('age1');

/// The recipients file content: every configured key, one per line.
String recipientsText(PodshipConfig config, BackupConfig b) {
  final lines = <String>[];
  for (final r in b.recipients) {
    if (isPublicKey(r)) {
      lines.add(r.trim());
      continue;
    }
    final f = File(r.startsWith('~') ? expandHome(r) : p.join(config.root, r));
    if (!f.existsSync()) {
      throw ConfigException('backup recipient file $r not found');
    }
    lines.addAll(
      f
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#')),
    );
  }
  return '# Written by podship. Backups are encrypted to these keys.\n${lines.join('\n')}\n';
}

BackupConfig _need(EnvConfig env) =>
    env.backup ??
    (throw ConfigException('environments.${env.name}.backup is not set'));

/// Installs scripts, settings and recipients; shared by every backup step.
String backupSetup(PodshipConfig config, ResolvedEnv r) {
  final b = _need(r.env);
  return backupConfInstall(config, r) +
      (b.recipients.isEmpty
          ? ''
          : writeFile(recipientsPath(r.env), recipientsText(config, b)));
}

Plan planBackupNow(Ctx ctx, ResolvedEnv r) => Plan('backup ${r.env.name} now', [
  RemoteStep(
    'Back up ${r.env.database.name}',
    r.env.host,
    ctx.header(r.env) + backupSetup(ctx.config, r) + backupNow(r.env),
  ),
]);

Plan planDrill(Ctx ctx, ResolvedEnv r, String? stamp) => Plan(
  'restore drill for ${r.env.name}${stamp == null ? ' (newest backup)' : ' ($stamp)'}',
  [
    RemoteStep(
      'Restore into a throwaway container and compare row counts',
      r.env.host,
      '${ctx.header(r.env)}${backupSetup(ctx.config, r)}'
          '${shq('${r.env.libDir}/restore.sh')} ${shq(backupConfPath(r.env))} drill ${stamp == null ? '' : shq(stamp)}\n',
    ),
  ],
);

Plan planRestore(
  Ctx ctx,
  ResolvedEnv r, {
  String? stamp,
  String? dumpFile,
  EnvConfig? from,
  bool volumes = false,
}) {
  final env = r.env;
  if (from != null) {
    // A backup folder of another environment, maybe on another server:
    // copy it over (through this machine when the servers differ), check
    // its checksums, and restore it.
    final fb = _need(from);
    if (stamp == null) throw Aborted('--from needs a backup stamp');
    final src = '${fb.dir}/${fb.layout.plain}/$stamp';
    final dst = '${env.podshipHome}/incoming/${from.composeProject}-$stamp';
    return Plan(
      'restore ${env.name} from ${from.name} backup $stamp${volumes ? ' with volumes' : ''}',
      [
        LocalStep('Copy backup $stamp from ${from.name} to ${env.name}', [
          'bash',
          '-c',
          'set -o pipefail; ssh ${from.host} ${shq('tar -C ${shq(src)} -cf - .')} | '
              'ssh ${env.host} ${shq('rm -rf ${shq(dst)} && mkdir -p ${shq(dst)} && chmod 700 ${shq(dst)} && tar -x -C ${shq(dst)}')}',
        ]),
        RemoteStep(
          'Back up, stop, rename the database, restore${volumes ? ' (with volumes)' : ''}, start',
          env.host,
          '${ctx.header(env)}${backupSetup(ctx.config, r)}'
              '${shq('${env.libDir}/restore.sh')} ${shq(backupConfPath(env))} restore '
              '--confirmed ${shq(ctx.config.project)} --dir ${shq(dst)}${volumes ? ' --volumes' : ''}\n',
        ),
      ],
    );
  }
  return Plan(
    'restore the ${env.name} database from ${stamp ?? dumpFile ?? 'the newest backup'}',
    [
      if (dumpFile != null)
        ActionStep(
          'Upload $dumpFile',
          'scp to ${remoteSpec(env.host, '${env.podshipHome}/upload.dump')}',
          () async {
            final res =
                await Process.run(isLocalHost(env.host) ? 'cp' : 'scp', [
                  if (!isLocalHost(env.host)) ...ctx.ssh.options(),
                  dumpFile,
                  remoteSpec(env.host, '${env.podshipHome}/upload.dump'),
                ]);
            if (res.exitCode != 0) throw Aborted('scp failed: ${res.stderr}');
          },
        ),
      RemoteStep(
        'Back up, stop, rename the database, restore, start',
        env.host,
        '${ctx.header(env)}${backupSetup(ctx.config, r)}'
            '${shq('${env.libDir}/restore.sh')} ${shq(backupConfPath(env))} restore '
            '--confirmed ${shq(ctx.config.project)} '
            '${dumpFile != null
                ? '--dump ${shq('${env.podshipHome}/upload.dump')}'
                : stamp == null
                ? ''
                : shq(stamp)}'
            '${volumes && dumpFile == null ? ' --volumes' : ''}\n',
      ),
    ],
  );
}

/// Plans `backup schedule`: systemd on Linux, launchd on macOS. An
/// existing unit with the same name is replaced in place (adopted), so a
/// server never runs two schedules for one environment.
Plan planSchedule(
  Ctx ctx,
  ResolvedEnv r, {
  required bool macos,
  bool remove = false,
}) {
  final env = r.env;
  final b = _need(env);
  if (remove) {
    return Plan('remove the backup schedule of ${env.name}', [
      RemoteStep(
        'Disable ${b.unit}',
        env.host,
        macos
            ? '${ctx.header(env)}launchctl bootout gui/\$(id -u)/${shq(b.unit)} 2>/dev/null || true\nrm -f ~/Library/LaunchAgents/${shq('${b.unit}.plist')}\n'
            : '${ctx.header(env)}systemctl disable --now ${shq('${b.unit}.timer')} || true\nrm -f /etc/systemd/system/${shq('${b.unit}.timer')} /etc/systemd/system/${shq('${b.unit}.service')}\nsystemctl daemon-reload\n',
      ),
    ]);
  }
  final setup = backupSetup(ctx.config, r);
  if (macos) {
    final plist = launchdPlist(
      ctx.config,
      r,
      path:
          '${env.remotePath ?? '/opt/homebrew/bin'}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
    );
    return Plan('backup schedule for ${env.name} (launchd)', [
      RemoteStep(
        'Install scripts, settings and recipients',
        env.host,
        ctx.header(env) + setup,
      ),
      for (final old in b.replaces)
        RemoteStep(
          'Disable the old schedule $old',
          env.host,
          // Unloaded and renamed, so it does not come back at the next login.
          'launchctl bootout gui/\$(id -u)/${shq(old)} 2>/dev/null || true\n'
          'f="\$HOME/Library/LaunchAgents/"${shq('$old.plist')}\n'
          '[ -f "\$f" ] && mv "\$f" "\$f.disabled-by-podship" || true\n',
        ),
      RemoteStep(
        'Install launch agent ${b.unit} (${r.backupSchedule}, Mac local time)',
        env.host,
        '${ctx.header(env)}mkdir -p ${shq('${env.podshipHome}/log')}\n'
            '${writeFile('\$HOME/Library/LaunchAgents/${b.unit}.plist', plist).replaceAll("'\$HOME/Library", '"\$HOME"\'/Library')}'
            'launchctl bootout gui/\$(id -u)/${shq(b.unit)} 2>/dev/null || true\n'
            'launchctl bootstrap gui/\$(id -u) "\$HOME/Library/LaunchAgents/${b.unit}.plist"\n'
            'launchctl print gui/\$(id -u)/${shq(b.unit)} | grep -E "state|path" | head -3\n',
      ),
    ]);
  }
  final units = systemdUnits(ctx.config, r);
  return Plan('backup schedule for ${env.name} (systemd)', [
    RemoteStep(
      'Install scripts, settings and recipients',
      env.host,
      ctx.header(env) + setup,
    ),
    for (final old in b.replaces)
      RemoteStep(
        'Disable the old schedule $old (its files stay)',
        env.host,
        'systemctl disable --now ${shq('$old.timer')} 2>/dev/null || true\n'
            'systemctl is-active ${shq('$old.timer')} || echo "$old is off"\n',
      ),
    RemoteStep(
      'Install ${b.unit}.service and .timer (${r.backupSchedule})',
      env.host,
      '${ctx.header(env)}'
          'mkdir -p ${shq(env.etcDir)}\nfor f in ${shq('${b.unit}.service')} ${shq('${b.unit}.timer')}; do\n'
          '  if [ -f /etc/systemd/system/\$f ]; then cp /etc/systemd/system/\$f ${shq(env.etcDir)}/\$f.before-podship-\$(date +%Y%m%d%H%M%S); fi\n'
          'done\n'
          'mkdir -p ${shq(env.etcDir)}\n'
          '${writeFile('/etc/systemd/system/${b.unit}.service', units.service)}'
          '${writeFile('/etc/systemd/system/${b.unit}.timer', units.timer)}'
          'systemctl daemon-reload\n'
          'systemctl enable --now ${shq('${b.unit}.timer')}\n'
          'systemctl list-timers ${shq('${b.unit}.timer')} --no-pager\n',
    ),
  ]);
}

/// Plans `backup pull`: copy the encrypted backups to this machine, never
/// delete anything here, and check that the newest one decrypts and that
/// its checksums match.
Plan planPull(Ctx ctx, EnvConfig env) {
  final b = _need(env);
  final dir = b.offsiteDir;
  if (dir == null) {
    throw ConfigException(
      'environments.${env.name}.backup.offsite.dir is not set',
    );
  }
  final local = expandHome(dir);
  final ids = [for (final i in b.offsiteIdentities) expandHome(i)];
  return Plan('pull ${env.name} backups to $local', [
    LocalStep('Copy new encrypted backups', [
      'bash',
      '-c',
      'mkdir -p ${shq(local)} && chmod 700 ${shq(local)} && '
          // The server is this machine: a plain copy, never overwriting.
          '${isLocalHost(env.host) ? 'for f in ${shq('${expandHome(b.dir)}/${b.layout.encrypted}')}/*.tar.age; do '
                    '[ -e "\$f" ] && cp -np "\$f" ${shq('$local/')}; done; true' : 'rsync -t --ignore-existing -e ${shq(ctx.ssh.rsyncShell())} '
                    '${shq('${env.host}:${b.dir}/${b.layout.encrypted}/')}\'*.tar.age\' ${shq('$local/')}'}',
    ]),
    LocalStep('Check that the newest copy decrypts and its checksums match', [
      'bash',
      '-c',
      verifyNewestScript(local, ids),
    ]),
  ]);
}

/// The local script that checks the newest encrypted backup in [dir].
String verifyNewestScript(String dir, List<String> identities) =>
    '''
set -euo pipefail
newest=\$(ls -1 ${shq(dir)}/*.tar.age 2>/dev/null | sort | tail -1)
[ -n "\$newest" ] || { echo "no backups in $dir"; exit 1; }
tmp=\$(mktemp -d); trap 'rm -rf "\$tmp"' EXIT
ok=""
for id in ${identities.map(shq).join(' ')}; do
  [ -f "\$id" ] || continue
  if age -d -i "\$id" "\$newest" 2>/dev/null | tar -x -C "\$tmp" 2>/dev/null; then ok="\$id"; break; fi
done
[ -n "\$ok" ] || { echo "cannot decrypt \$newest with: ${identities.join(', ')}"; exit 1; }
stamp=\$(basename "\$newest" .tar.age)
(cd "\$tmp/\$stamp" && shasum -a 256 -c --status SHA256SUMS)
echo "ok: \$(ls -1 ${shq(dir)}/*.tar.age | wc -l | tr -d ' ') backups here; the newest (\$stamp) decrypts with \$ok and its checksums match"
''';
