// Zero-downtime switch (switch: blue_green).
//
// The new release starts next to the running one in its own compose
// project (`<project>-blue` or `<project>-green`). Its containers publish
// no host ports; they join the network `<project>-front` with aliases like
// `green-server`. A small nginx container, `<project>-front`, owns the
// environment's loopback ports and passes TCP to the active color (nginx
// `stream`, so HTTP, WebSockets and anything else pass unchanged). When
// the new color answers /health (and /readyz) from inside its container,
// podship rewrites the front config and reloads nginx: open connections
// finish on the old workers, new ones go to the new color. (The front
// mounts the config folder, not the file: a file mount keeps the old inode
// after an atomic rewrite.) Then the old
// color stops. Rollback is the same flip back.
//
// Both colors must share the data: the database runs outside the release
// (database.mode: shared), and named volumes keep the base project's
// names (`<project>_<volume>`), so backups and restores see the same
// volumes. Without a shared database the deploy switches in place and says
// why.

import 'dart:convert';

import '../config/config.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import 'context.dart';
import 'resolve.dart';
import 'scripts.dart';

/// Why [env] cannot switch blue/green, or null when it can.
String? blueGreenBlocker(EnvConfig env) {
  if (env.switchMode != SwitchMode.blueGreen) return 'switch is in_place';
  if (env.database.mode != DatabaseMode.shared) {
    return 'switch: blue_green needs database.mode: shared (the database '
        'must live outside the release, or each color gets its own); '
        'switching in place';
  }
  if (env.serverpod.replicas > 1) {
    return 'switch: blue_green and serverpod.replicas > 1 are not combined '
        'yet; switching in place';
  }
  return null;
}

/// One published port of a compose service.
class PublishedPort {
  PublishedPort(this.service, this.hostIp, this.published, this.target);
  final String service;
  final String hostIp;
  final int published;
  final int target;

  @override
  bool operator ==(Object other) =>
      other is PublishedPort &&
      other.service == service &&
      other.published == published &&
      other.target == target &&
      other.hostIp == hostIp;
  @override
  int get hashCode => Object.hash(service, published, target, hostIp);
}

/// Reads the published ports and the named volumes from
/// `docker compose config --format json`.
({List<PublishedPort> ports, List<String> volumes}) parseComposeConfig(
  String json,
) {
  final j = jsonDecode(json) as Map<String, Object?>;
  final ports = <PublishedPort>[];
  final services = (j['services'] as Map?) ?? const {};
  for (final e in services.entries) {
    final svc = e.value as Map;
    for (final p in (svc['ports'] as List? ?? const [])) {
      final m = p as Map;
      final pub = int.tryParse('${m['published'] ?? ''}');
      final tgt = int.tryParse('${m['target'] ?? ''}');
      if (pub == null || tgt == null) continue;
      ports.add(
        PublishedPort('${e.key}', '${m['host_ip'] ?? '127.0.0.1'}', pub, tgt),
      );
    }
  }
  return (
    ports: ports,
    volumes: [for (final k in ((j['volumes'] as Map?) ?? const {}).keys) '$k'],
  );
}

/// The other color.
String otherColor(String? active) => active == 'blue' ? 'green' : 'blue';

/// The compose project of [color].
String colorProject(String composeProject, String color) =>
    '$composeProject-$color';

/// The network that the front and both colors share.
String frontNetwork(String composeProject) => '$composeProject-front';

/// The front container.
String frontContainer(String composeProject) => '$composeProject-front';

/// The compose override of a color: no host ports, the front network with
/// `<color>-<service>` aliases, and the volumes of the base project.
String colorOverride({
  required String composeProject,
  required String color,
  required List<PublishedPort> ports,
  required List<String> volumes,
}) {
  final net = frontNetwork(composeProject);
  final b = StringBuffer()
    ..writeln('# Written by podship: the $color color of $composeProject.')
    ..writeln('services:');
  final services = {for (final p in ports) p.service}.toList()..sort();
  for (final s in services) {
    b
      ..writeln('  ${jsonEncode(s)}:')
      ..writeln('    ports: !reset []')
      ..writeln('    networks:')
      ..writeln('      default: {}')
      ..writeln('      ${jsonEncode(net)}:')
      ..writeln('        aliases: [${jsonEncode('$color-$s')}]');
  }
  b
    ..writeln('networks:')
    ..writeln('  ${jsonEncode(net)}:')
    ..writeln('    external: true');
  if (volumes.isNotEmpty) {
    b.writeln('volumes:');
    for (final v in volumes) {
      b
        ..writeln('  ${jsonEncode(v)}:')
        ..writeln('    name: ${jsonEncode('${composeProject}_$v')}');
    }
  }
  return b.toString();
}

/// The nginx config of the front: one TCP proxy per published port, to the
/// [color]'s alias.
String frontConf(List<PublishedPort> ports, String color) {
  final b = StringBuffer()
    ..writeln('# Written by podship: the front of the $color color.')
    ..writeln('worker_processes 1;')
    ..writeln('events { worker_connections 4096; }')
    ..writeln('stream {')
    ..writeln('  resolver 127.0.0.11 valid=5s;');
  for (final p in ports) {
    b
      ..writeln('  server {')
      ..writeln('    listen ${p.published};')
      ..writeln('    set \$up $color-${p.service}:${p.target};')
      ..writeln('    proxy_pass \$up;')
      ..writeln('    proxy_timeout 3600s;')
      ..writeln('  }');
  }
  b.writeln('}');
  return b.toString();
}

/// Starts release [id] as [color], writes its override, and waits until its
/// server answers [healthPaths] inside the container.
String startColorScript({
  required EnvLayout l,
  required String composeProject,
  required String id,
  required String color,
  required String override,
  required String serverService,
  required int serverPort,
  required List<String> healthPaths,
  int waitSeconds = 180,
}) {
  final proj = colorProject(composeProject, color);
  final file = '${l.release(id)}/.podship/bg-$proj.yml';
  final b = StringBuffer()
    ..writeln(
      'docker network inspect ${frontNetwork(composeProject)} >/dev/null 2>&1 || docker network create ${frontNetwork(composeProject)} >/dev/null',
    )
    ..write(writeFile(file, override))
    ..writeln(
      'PODSHIP_COMPOSE_PROJECT=$proj ${shq(l.composeSh(id))} up -d --no-build --remove-orphans',
    )
    ..writeln(
      'c=\$(docker ps -q --filter label=com.docker.compose.project=$proj --filter label=com.docker.compose.service=$serverService | head -1)',
    )
    ..writeln(
      '[ -n "\$c" ] || { echo "no $serverService container in $proj" >&2; exit 1; }',
    );
  for (final h in healthPaths) {
    b
      ..writeln('ok=; for i in \$(seq $waitSeconds); do')
      ..writeln(
        '  if docker exec "\$c" wget -qO- ${shq('http://127.0.0.1:$serverPort$h')} >/dev/null 2>&1; then ok=1; break; fi; sleep 1',
      )
      ..writeln('done')
      ..writeln(
        '[ -n "\$ok" ] || { echo "$color does not answer $h" >&2; docker logs --tail 40 "\$c" >&2; exit 1; }',
      )
      ..writeln('echo "$color answers $h"');
  }
  return b.toString();
}

/// Points the front at [color] (starting the front the first time, after
/// [stopBase] frees the ports) and records it.
String flipScript({
  required EnvLayout l,
  required String composeProject,
  required String color,
  required List<PublishedPort> ports,
  String stopBase = '',
}) {
  final front = frontContainer(composeProject);
  final conf = '${l.state}/front/nginx.conf';
  final publish = {
    for (final p in ports) '-p ${p.hostIp}:${p.published}:${p.published}',
  }.join(' ');
  return '''
${writeFile(conf, frontConf(ports, color))}if docker container inspect $front >/dev/null 2>&1; then
  docker exec $front nginx -t -q -c /etc/podship-front/nginx.conf
  docker exec $front nginx -s reload -c /etc/podship-front/nginx.conf
else
$stopBase  docker run -d --name $front --restart unless-stopped --label podship.front=$composeProject --network ${frontNetwork(composeProject)} $publish -v ${shq('${l.state}/front')}:/etc/podship-front:ro nginx:1.27-alpine nginx -c /etc/podship-front/nginx.conf -g 'daemon off;' >/dev/null
fi
echo ${colorProject(composeProject, color)} > ${shq('${l.state}/active-project')}
echo "front → $color"
''';
}

/// Stops the containers of the color that no longer takes traffic (kept,
/// not removed, so a rollback starts it fast).
String stopColorScript(String composeProject, String color) {
  final proj = colorProject(composeProject, color);
  return 'ids=\$(docker ps -q --filter label=com.docker.compose.project=$proj)\n'
      '[ -z "\$ids" ] || docker stop -t 30 \$ids >/dev/null\n'
      'echo "stopped $proj"\n';
}

/// The first blue/green deploy: the base project (no color) holds the
/// ports; it stops right before the front starts (a second or two).
String stopBaseScript(String composeProject) =>
    '  ids=\$(docker ps -q --filter label=com.docker.compose.project=$composeProject)\n'
    '  [ -z "\$ids" ] || docker stop -t 30 \$ids >/dev/null\n';

/// The steps of a blue/green switch to release [id], and the recovery.
/// The color is read from the server when the step runs.
({Step start, Step stopOld, List<Step> recovery}) blueGreenSteps(
  Ctx ctx,
  ResolvedEnv r,
  String id, {
  required String? old,
  required String action,
}) {
  final env = r.env;
  final l = EnvLayout(env);
  final cp = env.composeProject;
  String? active; // the compose project that had the traffic
  String? color;
  List<PublishedPort> ports = const [];
  Future<String> q(String s) => ctx.query(env, s);
  Future<void> stream(String script) async {
    final code = await ctx.ssh.lines(
      env.host,
      ctx.header(env) + script,
      (line, err) => ctx.log.output(line, stderr: err),
    );
    if (code != 0) throw Aborted('blue/green: exit code $code');
  }

  final start = ActionStep(
    'Start $id next to ${old ?? 'nothing'} (blue/green)',
    'compose project $cp-blue or -green without host ports; wait for /health and /readyz inside it; flip the front ($cp-front, nginx stream); record',
    () async {
      active = (await q(
        'cat ${shq('${l.state}/active-project')} 2>/dev/null || true\n',
      )).trim();
      color = otherColor(
        active == '$cp-blue'
            ? 'blue'
            : active == '$cp-green'
            ? 'green'
            : null,
      );
      final proj = colorProject(cp, color!);
      final cfg = parseComposeConfig(
        await q(
          'PODSHIP_COMPOSE_PROJECT=$cp ${shq(l.composeSh(id))} config --format json\n',
        ),
      );
      ports = cfg.ports;
      final health = Uri.parse(r.healthUrl);
      final hp = ports.where((p) => p.published == health.port).firstOrNull;
      if (hp == null) {
        throw Aborted(
          'blue/green: no service publishes port ${health.port} of ${r.healthUrl}',
        );
      }
      final readiness = r.readinessUrl == null
          ? null
          : Uri.parse(r.readinessUrl!).path;
      await stream(
        startColorScript(
          l: l,
          composeProject: cp,
          id: id,
          color: color!,
          override: colorOverride(
            composeProject: cp,
            color: color!,
            ports: ports,
            volumes: cfg.volumes,
          ),
          serverService: hp.service,
          serverPort: hp.target,
          healthPaths: [health.path, ?readiness],
        ),
      );
      await stream(
        flipScript(
          l: l,
          composeProject: cp,
          color: color!,
          ports: ports,
          stopBase: active!.isEmpty ? stopBaseScript(cp) : '',
        ),
      );
      await stream(
        'cd ${shq(l.dir)}\n'
        'ln -sfn ${shq('releases/$id')} current.podship-new\n'
        '_mvlink current.podship-new current\n'
        'echo "\$(date -u +%Y-%m-%dT%H:%M:%SZ) $action $id as $proj${old == null ? '' : ' from $old'} by \${SUDO_USER:-\$USER}" >> ${shq(l.history)}\n',
      );
      ctx.log.info('$proj takes the traffic');
    },
  );
  final stopOld = ActionStep(
    'Stop the old color',
    'docker stop (kept for a fast rollback)',
    () async {
      if (active == null || active!.isEmpty) return;
      await stream(
        stopColorScript(cp, active == '$cp-blue' ? 'blue' : 'green'),
      );
    },
  );
  final recovery = <Step>[
    ActionStep(
      'Flip the front back',
      'start the old color again (or the base project) and point the front at it',
      () async {
        if (color == null) return;
        if (active == null || active!.isEmpty) {
          await stream(
            'docker rm -f ${frontContainer(cp)} >/dev/null 2>&1 || true\n'
            'rm -f ${shq('${l.state}/active-project')}\n'
            'ids=\$(docker ps -aq --filter label=com.docker.compose.project=$cp)\n'
            '[ -z "\$ids" ] || docker start \$ids >/dev/null\n',
          );
        } else {
          final back = active == '$cp-blue' ? 'blue' : 'green';
          await stream(
            'ids=\$(docker ps -aq --filter label=com.docker.compose.project=$active)\n'
            '[ -z "\$ids" ] || docker start \$ids >/dev/null\n'
            '${flipScript(l: l, composeProject: cp, color: back, ports: ports)}',
          );
        }
        await stream(stopColorScript(cp, color!));
        if (old != null) {
          await stream(
            'cd ${shq(l.dir)}\n'
            'ln -sfn ${shq('releases/$old')} current.podship-new\n'
            '_mvlink current.podship-new current\n',
          );
        }
      },
    ),
  ];
  return (start: start, stopOld: stopOld, recovery: recovery);
}
