// rollback, promote, adopt, restart: the other ways to change the running
// release.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../release/release.dart';
import '../remote/ssh.dart';
import 'backup_ops.dart';
import 'bluegreen.dart';
import 'context.dart';
import 'deploy.dart';
import 'migrations_check.dart';
import 'resolve.dart';
import 'scheduler_ops.dart' show agentStep;
import 'scripts.dart';
import 'state.dart';

/// The switch, the health check and the recovery, shared by every command
/// that changes the running release.
({List<Step> steps, List<Step> recovery}) switchSteps(
  Ctx ctx,
  ResolvedEnv r,
  String id, {
  required String? old,
  required String action,
  bool inPlace = false,
}) {
  final env = r.env;
  final l = EnvLayout(env);
  if (blueGreenBlocker(env) == null && !inPlace) {
    final bg = blueGreenSteps(ctx, r, id, old: old, action: action);
    return (
      steps: [
        bg.start,
        HealthStep(
          'Health check',
          env.host,
          r.healthUrls,
          publicUrls: r.publicHealthUrls,
          attempts: env.health.attempts,
          intervalSeconds: env.health.intervalSeconds,
        ),
        bg.stopOld,
      ],
      recovery: bg.recovery,
    );
  }
  return (
    steps: [
      RemoteStep(
        'Switch to $id',
        env.host,
        ctx.header(env) + switchTo(l, id, action: action, from: old),
      ),
      HealthStep(
        'Health check',
        env.host,
        r.healthUrls,
        publicUrls: r.publicHealthUrls,
        attempts: env.health.attempts,
        intervalSeconds: env.health.intervalSeconds,
      ),
      if (r.readinessUrl != null)
        HealthStep(
          'Serverpod readiness (/readyz)',
          env.host,
          [r.readinessUrl!],
          attempts: env.health.attempts,
          intervalSeconds: env.health.intervalSeconds,
        ),
    ],
    recovery: [
      if (old != null) ...[
        RemoteStep(
          'Switch back to $old',
          env.host,
          ctx.header(env) + switchTo(l, old, action: 'auto-rollback', from: id),
        ),
        HealthStep(
          'Health check of $old',
          env.host,
          r.healthUrls,
          attempts: env.health.attempts,
          intervalSeconds: env.health.intervalSeconds,
        ),
      ],
    ],
  );
}

/// The migration folder names of [dir] on [env]'s host.
Future<Set<String>> remoteMigrationNames(
  Ctx ctx,
  EnvConfig env,
  String dir,
) async => (await ctx.query(env, 'ls -1 ${shq(dir)} 2>/dev/null || true\n'))
    .split('\n')
    .map((x) => x.trim())
    .where((x) => x.isNotEmpty && !x.contains('.'))
    .toSet();

/// The step that stops a blue/green [command] when the two releases do not
/// share a backward-compatible schema: the migrations of [aDir] (on [aEnv])
/// that [bDir] (on [bEnv]) does not have, and the other way around. Both
/// releases run on the same database during the switch.
Step migrationsCheckStep(
  Ctx ctx, {
  required String command,
  required EnvConfig aEnv,
  required String aDir,
  required EnvConfig bEnv,
  required String bDir,
}) => ActionStep(
  'Check the migrations (blue/green)',
  'both releases run on the same schema during the switch: the migrations one has and the other lacks must be backward compatible',
  () async {
    final aNames = await remoteMigrationNames(ctx, aEnv, aDir);
    final bNames = await remoteMigrationNames(ctx, bEnv, bDir);
    final issues = <MigrationIssue>{
      ...checkMigrations(
        parseRemoteMigrations(
          await ctx.query(aEnv, remoteMigrationsScript(aDir, bNames)),
        ),
      ),
      ...checkMigrations(
        parseRemoteMigrations(
          await ctx.query(bEnv, remoteMigrationsScript(bDir, aNames)),
        ),
      ),
    }.toList();
    if (issues.isNotEmpty) {
      throw Aborted(destructiveMessage(issues, command: command));
    }
    ctx.log.info('migrations: backward compatible');
  },
);

/// Plans `rollback`. Code only, unless [withDb] names a backup stamp: then
/// the database is restored first, through the same path as
/// `backup restore`.
Plan planRollback({
  required Ctx ctx,
  required ResolvedEnv r,
  required EnvState state,
  String? to,
  String? withDb,
  bool allowDestructiveMigrations = false,
}) {
  final env = r.env;
  final l = EnvLayout(env);
  final target =
      to ?? previousRelease(state.ids, state.current, failed: state.failed);
  if (target == null) throw Aborted('no release to roll back to');
  if (!state.ids.contains(target)) {
    throw Aborted(
      'release $target is not on ${env.host}. Known: ${state.ids.join(', ')}',
    );
  }
  if (target == state.current) throw Aborted('$target is already running');
  final bg = blueGreenBlocker(env) == null;
  final sw = switchSteps(
    ctx,
    r,
    target,
    old: state.current,
    action: 'rollback',
    inPlace: allowDestructiveMigrations,
  );
  final pkg = ctx.config.serverPackage;
  final steps = <Step>[
    if (bg && allowDestructiveMigrations)
      ActionStep(
        'Switch mode: in place',
        '--allow-destructive-migrations: switching in place for this rollback',
        () async => ctx.log.warn(
          '--allow-destructive-migrations: switching in place for this rollback',
        ),
      ),
    // With a database restore the schema is the backup's: no check.
    if (bg &&
        !allowDestructiveMigrations &&
        withDb == null &&
        state.current != null)
      migrationsCheckStep(
        ctx,
        command: 'rollback',
        aEnv: env,
        aDir: '${l.release(state.current!)}/$pkg/migrations',
        bEnv: env,
        bDir: '${l.release(target)}/$pkg/migrations',
      ),
    if (withDb != null) ...[
      agentStep(ctx, env),
      RemoteStep(
        'Restore database backup $withDb',
        env.host,
        '${ctx.header(env)}${backupSetup(ctx.config, r)}'
            '${agentCommand(env, 'restore', ['--confirmed', ctx.config.project, withDb])}',
      ),
    ],
  ];
  final guardFrom = steps.length;
  steps.addAll(sw.steps);
  steps.add(
    RemoteStep(
      'Record',
      env.host,
      ctx.header(env) +
          (state.releases.any((x) => x.id == target && x.status == 'failed')
              ? setStatus(l, target, 'ok')
              : 'true\n'),
    ),
  );
  return Plan(
    // rollbackTarget reads the last " to <id>": nothing after it may say " to ".
    'rollback ${ctx.config.project} ${env.name} from ${state.current} to $target'
    '${withDb == null ? ' (code only)' : ' with database backup $withDb'}',
    steps,
    recovery: sw.recovery,
    guardFrom: guardFrom,
    guardTo: guardFrom + sw.steps.length - 1,
  );
}

/// The release a plan of [planRollback] switches to (its title names it;
/// a blue/green rollback has no `Switch to` step).
String rollbackTarget(Plan plan) =>
    RegExp(r' to (\S+)').allMatches(plan.title).last.group(1)!;

/// Plans `restart`: recreate the containers of the current release, for
/// example after `env set` or `secret set`.
///
/// With `switch: blue_green`, a restart of the whole release is a
/// blue/green start of the current release in the other color (no
/// downtime). Named stable services (the database) are recreated in the
/// base project (compose.sh routes them there and joins them to the color
/// networks again). Other named services are recreated in place in the
/// active color: a short outage for them.
Plan planRestart({
  required Ctx ctx,
  required ResolvedEnv r,
  required EnvState state,
  List<String> services = const [],
}) {
  final env = r.env;
  final l = EnvLayout(env);
  final current = state.current;
  if (current == null) {
    throw Aborted('nothing is deployed to ${env.name}');
  }
  final health = HealthStep(
    'Health check',
    env.host,
    r.healthUrls,
    publicUrls: r.publicHealthUrls,
    attempts: env.health.attempts,
    intervalSeconds: env.health.intervalSeconds,
  );
  if (blueGreenBlocker(env) == null) {
    final stable = env.stableServices;
    if (services.isEmpty) {
      final sw = switchSteps(ctx, r, current, old: current, action: 'restart');
      return Plan(
        'restart ${env.name} ($current, blue/green: the other color starts, then takes the traffic)',
        sw.steps,
        recovery: sw.recovery,
        guardFrom: 0,
      );
    }
    final named = services.where(stable.contains).toList();
    if (named.isNotEmpty && named.length != services.length) {
      throw Aborted(
        'restart either the stable services (${stable.join(', ')}, in the '
        'base project) or services of the active color, not both',
      );
    }
    final warn = named.isNotEmpty
        ? '${named.join(', ')} restart in the base project ${env.composeProject}; '
              'both colors lose the database for a moment'
        : '${services.join(', ')} restart in place in the active color: a '
              'short outage for them. `podship restart` with no services '
              'restarts the whole release blue/green, without downtime';
    return Plan('restart ${env.name} ($current)', [
      ActionStep('Warning', warn, () async => ctx.log.warn(warn)),
      RemoteStep(
        'Recreate ${services.join(', ')}',
        env.host,
        '${ctx.header(env)}${shq(l.currentComposeSh)} up -d --no-build --force-recreate --no-deps ${services.map(shq).join(' ')}\n',
      ),
      health,
    ]);
  }
  return Plan('restart ${env.name} ($current)', [
    RemoteStep(
      'Recreate containers',
      env.host,
      '${ctx.header(env)}${shq(l.currentComposeSh)} up -d --no-build --force-recreate ${services.isEmpty ? '' : '--no-deps '}${services.map(shq).join(' ')}\n',
    ),
    health,
  ]);
}

/// Reads the compose files of release [id] on [env] into [localRoot].
Future<void> fetchComposeFiles(
  Ctx ctx,
  EnvConfig env,
  String id,
  List<String> files,
  String localRoot,
) async {
  final l = EnvLayout(env);
  for (final f in files) {
    final text = await ctx.query(
      env,
      'cat ${shq(p.posix.join(l.release(id), f))}',
    );
    final out = File(p.join(localRoot, f));
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(text);
  }
}

/// Plans `promote`: run on [to] the exact release (files and images) that
/// runs on [from]. No build happens.
Future<Plan> planPromote({
  required Ctx ctx,
  required EnvConfig from,
  required EnvState fromState,
  required ResolvedEnv to,
  required EnvState toState,
  required String release,
  required String workDir,
  bool allowDestructiveMigrations = false,
}) async {
  final config = ctx.config;
  final src = EnvLayout(from);
  final env = to.env;
  final dst = EnvLayout(env);
  if (!fromState.ids.contains(release)) {
    throw Aborted('release $release is not on ${from.name}');
  }
  final info = fromState.releases.firstWhere((x) => x.id == release);
  if (info.status != 'ok' && info.status != 'adopted') {
    throw Aborted(
      'release $release is ${info.status} on ${from.name}; promote only healthy releases',
    );
  }
  if (toState.ids.contains(release)) {
    throw Aborted(
      '$release is already on ${env.name}; use rollback --to $release',
    );
  }
  final sameHost = from.host == env.host;
  final srcImages = info.meta?.images ?? const <String>[];
  final pinned = <String, String>{};
  for (final img in srcImages) {
    final name = img.split(':').first;
    final prefix = '${from.composeProject}-';
    final service = name.startsWith(prefix)
        ? name.substring(prefix.length)
        : name;
    pinned[service] = imageName(env.composeProject, service, release);
  }
  final stage = '${dst.state}/promote-$release';
  final bg = blueGreenBlocker(env) == null;
  final pkg = config.serverPackage;
  final steps = <Step>[
    if (bg && allowDestructiveMigrations)
      ActionStep(
        'Switch mode: in place',
        '--allow-destructive-migrations: switching in place for this promote',
        () async => ctx.log.warn(
          '--allow-destructive-migrations: switching in place for this promote',
        ),
      )
    else if (bg && toState.current != null)
      migrationsCheckStep(
        ctx,
        command: 'promote',
        aEnv: from,
        aDir: '${src.release(release)}/$pkg/migrations',
        bEnv: env,
        bDir: '${dst.release(toState.current!)}/$pkg/migrations',
      ),
    ActionStep(
      'Write release metadata for ${env.name}',
      'read the compose files of $release from ${from.name}; write .podship/',
      () async {
        await fetchComposeFiles(
          ctx,
          from,
          release,
          composeFilesOf(config, env),
          workDir,
        );
        writeReleaseMeta(
          config: config,
          r: to,
          releaseRoot: workDir,
          id: release,
          git: GitInfo(
            info.meta?.sha ?? 'unknown',
            dirty: info.meta?.dirty ?? false,
            ref: info.meta?.ref ?? '',
          ),
          promotedFrom: from.name,
          pinnedImages: pinned,
        );
      },
    ),
  ];
  final copyFiles =
      'rm -rf ${shq(stage)} && mkdir -p ${shq(stage)}\n'
      'cd ${shq(src.release(release))}\n'
      'tar --exclude=./.podship --exclude=./.env -cf - . | tar -x -C ${shq(stage)}\n'
      'rm -f ${shq('$stage/${env.secrets.passwordsLink}')}\n';
  final tags = [
    for (final img in srcImages)
      () {
        final name = img.split(':').first;
        final service = name.startsWith('${from.composeProject}-')
            ? name.substring(from.composeProject.length + 1)
            : name;
        return 'docker tag ${shq(img)} ${shq(pinned[service]!)}';
      }(),
  ].join('\n');
  if (sameHost) {
    steps.add(
      RemoteStep(
        'Copy files and tag images of $release',
        env.host,
        '${ctx.header(env)}mkdir -p ${shq(dst.releases)}\n$copyFiles$tags\n',
      ),
    );
  } else {
    steps.add(
      LocalStep('Copy files from ${from.host} to ${env.host}', [
        'bash',
        '-c',
        'set -o pipefail; ssh ${from.host} ${shq('tar -C ${src.release(release)} --exclude=./.podship --exclude=./.env -cf - .')} '
            '| ssh ${env.host} ${shq('rm -rf $stage && mkdir -p $stage ${dst.releases} && tar -x -C $stage && rm -f $stage/${env.secrets.passwordsLink}')}',
      ]),
    );
    steps.add(
      LocalStep('Copy images from ${from.host} to ${env.host}', [
        'bash',
        '-c',
        'set -o pipefail; ssh ${from.host} ${shq('docker save ${srcImages.join(' ')}')} | ssh ${env.host} docker load',
      ]),
    );
    steps.add(RemoteStep('Tag images', env.host, '${ctx.header(env)}$tags\n'));
  }
  steps.addAll([
    UploadStep(
      'Upload release metadata',
      env.host,
      p.join(workDir, '.podship'),
      '$stage/.podship',
      delete: false,
    ),
    RemoteStep(
      'Create release $release on ${env.name}',
      env.host,
      '${ctx.header(env)}${makeReleaseScript(to, release, from: stage)}rm -rf ${shq(stage)}\n',
    ),
    if (env.backup != null && env.backup!.beforeDeploy) ...[
      agentStep(ctx, env),
      RemoteStep(
        'Back up the database before the switch',
        env.host,
        '${ctx.header(env)}'
            '${toState.dbRunning ? '' : 'echo "no database running yet: no backup"; exit 0\n'}'
            '${backupSetup(config, to)}${backupNow(env)}',
      ),
    ],
  ]);
  final sw = switchSteps(
    ctx,
    to,
    release,
    old: toState.current,
    action: 'promote from ${from.name}',
    inPlace: allowDestructiveMigrations,
  );
  final guardFrom = steps.length;
  steps.addAll(sw.steps);
  final toPrune = releasesToPrune(
    [...toState.ids, release],
    current: release,
    previous: toState.current,
    keep: env.keepReleases,
  );
  steps.add(
    RemoteStep(
      'Mark $release healthy and prune',
      env.host,
      ctx.header(env) + setStatus(dst, release, 'ok') + prune(dst, toPrune),
    ),
  );
  return Plan(
    'promote $release from ${from.name} to ${env.name}',
    steps,
    recovery: [
      RemoteStep(
        'Mark $release failed',
        env.host,
        ctx.header(env) + setStatus(dst, release, 'failed'),
      ),
      ...sw.recovery,
    ],
    guardFrom: guardFrom,
    guardTo: guardFrom + sw.steps.length - 1,
  );
}

/// What `adopt` found on the server.
class AdoptScan {
  AdoptScan(this.sha, this.images, this.composeTexts);

  /// The git commit of the existing checkout, or `nogit`.
  final String sha;

  /// Running image id by compose service.
  final Map<String, String> images;

  /// The compose files, by path relative to the compose directory.
  final Map<String, String> composeTexts;
}

Future<AdoptScan> scanForAdopt(
  Ctx ctx,
  EnvConfig env,
  String composeDir,
  List<String> composeFiles,
) async {
  final out = await ctx.query(env, '''
git -C ${shq(composeDir)} rev-parse HEAD 2>/dev/null || echo nogit
for c in \$(docker ps -q --filter label=com.docker.compose.project=${shq(env.composeProject)}); do
  docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}} {{.Image}}' "\$c"
done
''');
  final lines = out.trim().split('\n');
  final images = <String, String>{};
  for (final line in lines.skip(1)) {
    final parts = line.trim().split(' ');
    if (parts.length == 2) images[parts[0]] = parts[1];
  }
  final texts = <String, String>{
    for (final f in composeFiles)
      f: await ctx.query(env, 'cat ${shq(p.posix.join(composeDir, f))}'),
  };
  return AdoptScan(lines.first.trim(), images, texts);
}

/// Plans `adopt`: records a setup that podship did not create as a release,
/// without restarting anything. Its images are tagged with the release id,
/// so `rollback` can always come back to it.
Plan planAdopt({
  required Ctx ctx,
  required ResolvedEnv r,
  required EnvState state,
  required AdoptScan scan,
  required String composeDir,
  required DateTime now,
  required String workDir,
}) {
  final config = ctx.config;
  final env = r.env;
  final l = EnvLayout(env);
  if (state.current != null) {
    throw Aborted(
      '${env.name} already has a current release (${state.current})',
    );
  }
  if (scan.images.isEmpty) {
    throw Aborted(
      'no running containers of compose project ${env.composeProject}',
    );
  }
  final id = ReleaseId.create(
    now,
    scan.sha == 'nogit' ? 'nogit' : scan.sha,
    suffix: 'adopted',
  ).toString();
  // Pin only the services that have a build; the others keep their public
  // image names, so later deploys do not restart them for nothing.
  final built = builtServices(scan.composeTexts.values.toList());
  final pinned = {
    for (final s in scan.images.keys)
      if (built.contains(s)) s: imageName(env.composeProject, s, id),
  };
  final stage = '${l.state}/adopt-$id';
  final excludes = [
    '--exclude=/.git',
    '--exclude=/releases',
    '--exclude=/current',
    '--exclude=/.podship',
    '--exclude=/${env.secrets.envFile}',
    '--exclude=/${env.secrets.passwordsFile}',
  ].join(' ');
  final reg = state.registry..put(r.entry);
  return Plan('adopt the running ${env.composeProject} on ${env.host} as $id', [
    ActionStep(
      'Write release metadata',
      'write .podship/ for the compose files of $composeDir',
      () async {
        for (final e in scan.composeTexts.entries) {
          final out = File(p.join(workDir, e.key));
          out.parent.createSync(recursive: true);
          out.writeAsStringSync(e.value);
        }
        writeReleaseMeta(
          config: config,
          r: r,
          releaseRoot: workDir,
          id: id,
          git: GitInfo(scan.sha, ref: 'adopted'),
          pinnedImages: pinned,
        );
        File(
          p.join(workDir, '.podship', 'status'),
        ).writeAsStringSync('adopted\n');
      },
    ),
    RemoteStep('Copy $composeDir and tag the running images', env.host, '''
${ctx.header(env)}mkdir -p ${shq(l.releases)} ${shq(stage)}
rsync -a $excludes ${shq('$composeDir/')} ${shq('$stage/')}
${[for (final e in scan.images.entries)
      if (pinned.containsKey(e.key)) 'docker tag ${e.value} ${shq(pinned[e.key]!)}'].join('\n')}
'''),
    RegistryWriteStep(
      'Write the registry',
      env.host,
      env.registryPath,
      header: ctx.header(env),
      base: state.registryText,
      mine: reg.render(),
    ),
    UploadStep(
      'Upload release metadata',
      env.host,
      p.join(workDir, '.podship'),
      '$stage/.podship',
      delete: false,
    ),
    RemoteStep('Record release $id as current (nothing restarts)', env.host, '''
${ctx.header(env)}${makeReleaseScript(r, id, from: stage)}rm -rf ${shq(stage)}
cd ${shq(l.dir)}
ln -sfn ${shq('releases/$id')} current.podship-new && _mvlink current.podship-new current
mkdir -p ${shq(l.state)}
echo "\$(date -u +%FT%TZ) adopt $id by \${SUDO_USER:-\$USER}" >> ${shq(l.history)}
'''),
  ]);
}
