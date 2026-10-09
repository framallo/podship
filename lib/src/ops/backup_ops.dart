// backup: now, list, drill, restore, schedule, pull.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../plan/plan.dart';
import '../remote/ssh.dart';
import 'context.dart';
import 'deploy.dart';
import 'resolve.dart';
import 'scheduler_ops.dart';
import 'scripts.dart';
import '../server/registry.dart';

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

/// Installs settings and recipients; shared by every backup step.
String backupSetup(PodshipConfig config, ResolvedEnv r) {
  final b = _need(r.env);
  return backupConfInstall(config, r) +
      (b.recipients.isEmpty
          ? ''
          : writeFile(recipientsPath(r.env), recipientsText(config, b)));
}

Plan planBackupNow(Ctx ctx, ResolvedEnv r) => Plan('backup ${r.env.name} now', [
  agentStep(ctx, r.env),
  RemoteStep(
    'Back up ${r.env.database.name}',
    r.env.host,
    ctx.header(r.env) + backupSetup(ctx.config, r) + backupNow(r.env),
  ),
]);

Plan planDrill(Ctx ctx, ResolvedEnv r, String? stamp) => Plan(
  'restore drill for ${r.env.name}${stamp == null ? ' (newest backup)' : ' ($stamp)'}',
  [
    agentStep(ctx, r.env),
    RemoteStep(
      'Restore into a throwaway container and compare row counts',
      r.env.host,
      '${ctx.header(r.env)}${backupSetup(ctx.config, r)}'
          '${agentCommand(r.env, 'drill', [?stamp])}',
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
        agentStep(ctx, env),
        RemoteStep(
          'Back up, stop, rename the database, restore${volumes ? ' (with volumes)' : ''}, start',
          env.host,
          '${ctx.header(env)}${backupSetup(ctx.config, r)}'
              '${agentCommand(env, 'restore', ['--confirmed', ctx.config.project, '--dir', dst, if (volumes) '--volumes'])}',
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
      agentStep(ctx, env),
      RemoteStep(
        'Back up, stop, rename the database, restore, start',
        env.host,
        '${ctx.header(env)}${backupSetup(ctx.config, r)}'
            '${agentCommand(env, 'restore', [
              '--confirmed',
              ctx.config.project,
              if (dumpFile != null) ...['--dump', '${env.podshipHome}/upload.dump'],
              if (dumpFile == null && stamp != null) stamp,
              if (volumes && dumpFile == null) '--volumes',
            ])}',
      ),
    ],
  );
}

/// Plans `backup schedule`: the scripts, settings and recipients on the
/// server, and the backup job in its registry. No launchd, no systemd: the
/// machine's scheduler agent runs the job at its nightly run.
Plan planSchedule(
  Ctx ctx,
  ResolvedEnv r, {
  required Registry registry,
  required String registryText,
  bool remove = false,
}) {
  final env = r.env;
  _need(env);
  final job = backupJob(ctx, r);
  if (remove) {
    registry.removeJob(job.id);
    return Plan('remove the backup job of ${env.name}', [
      RegistryWriteStep(
        'Remove ${job.id} from the registry',
        env.host,
        env.registryPath,
        header: ctx.header(env),
        base: registryText,
        mine: registry.render(),
      ),
    ]);
  }
  registry.putJob(job);
  return Plan(
    'backup schedule for ${env.name} (nightly scheduler run at ${registry.scheduler.at})',
    [
      agentStep(ctx, env),
      RemoteStep(
        'Install settings and recipients',
        env.host,
        ctx.header(env) + backupSetup(ctx.config, r),
      ),
      RegistryWriteStep(
        'Write ${job.id} into the registry',
        env.host,
        env.registryPath,
        header: ctx.header(env),
        base: registryText,
        mine: registry.render(),
      ),
    ],
  );
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
# Only podship's stamps (2026-10-07T0330.tar.age): older archives with
# other names may share the folder and must not count as the newest.
newest=\$(ls -1 ${shq(dir)}/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*.tar.age 2>/dev/null | sort | tail -1)
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
