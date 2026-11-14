// Zero-downtime switch (switch: blue_green).
//
// The new release starts next to the running one in its own compose
// project (`<project>-blue` or `<project>-green`). Its containers publish
// no host ports; the ones that publish ports in the compose files join the
// network `<project>-front` with aliases like `green-nginx`. A small nginx
// container, `<project>-front`, owns the environment's loopback ports and
// passes TCP to the active color (nginx `stream`, so HTTP, WebSockets and
// anything else pass unchanged). When the new color answers /health (and
// /readyz) and the public checks from inside its container, podship
// rewrites the front config and reloads nginx: open connections finish on
// the old workers, new ones go to the new color. (The front mounts the
// config folder, not the file: a file mount keeps the old inode after an
// atomic rewrite.) Then the old color stops: first the services that
// publish ports (nginx quits gracefully and gets `blue_green.drain` seconds
// for open requests and streams), then the rest. Rollback is the same flip
// back.
//
// Both colors share the data, in one of two ways:
// - database.mode: shared: the database runs outside the release;
// - per-env database: the stable services (`blue_green.stable`, default the
//   database service) never run in a color. They stay in the base compose
//   project and join each color's default network (`<project>-<color>-net`,
//   external) with their service name as alias, so `postgres` resolves the
//   same way in both colors. In a color they are disabled (a profile) and
//   lose their volumes and ports, so a color can never start a second
//   database on the same files.
// Named volumes keep the base project's names (`<project>_<volume>`), so
// backups and restores see the same volumes.

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

  @override
  String toString() => '$service $hostIp:$published->$target';
}

/// One service of `docker compose config`.
class ComposeService {
  ComposeService(this.name, {this.dependsOn = const {}, this.networkMode});
  final String name;

  /// `depends_on`, as compose normalizes it (service -> settings).
  final Map<String, Object?> dependsOn;
  final String? networkMode;
}

/// What a color override needs from `docker compose config --format json`.
typedef ComposeInfo = ({
  List<PublishedPort> ports,
  List<String> volumes,
  Map<String, ComposeService> services,
});

/// Reads the published ports, the named volumes and the services from
/// `docker compose config --format json`.
ComposeInfo parseComposeConfig(String json) {
  final j = jsonDecode(json) as Map<String, Object?>;
  final ports = <PublishedPort>[];
  final out = <String, ComposeService>{};
  final services = (j['services'] as Map?) ?? const {};
  for (final e in services.entries) {
    final svc = e.value as Map;
    final deps = svc['depends_on'];
    out['${e.key}'] = ComposeService(
      '${e.key}',
      dependsOn: deps is Map
          ? {for (final d in deps.entries) '${d.key}': d.value}
          : deps is List
          ? {
              for (final d in deps)
                '$d': const {'condition': 'service_started'},
            }
          : const {},
      networkMode: svc['network_mode'] as String?,
    );
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
    services: out,
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

/// The default network of a color when it has stable services: created by
/// podship (external to compose) so the stable services can join it before
/// the color starts.
String colorNetwork(String composeProject, String color) =>
    '$composeProject-$color-net';

/// The profile that keeps the stable services out of a color.
const stableProfile = 'podship-stable';

/// The compose override of a color: no host ports, the front network with
/// `<color>-<service>` aliases, the volumes of the base project, and the
/// [stable] services disabled (their dependents start without them; they
/// reach them on the color's network).
String colorOverride({
  required String composeProject,
  required String color,
  required List<PublishedPort> ports,
  required List<String> volumes,
  Map<String, ComposeService> services = const {},
  List<String> stable = const [],
}) {
  final net = frontNetwork(composeProject);
  final publishing = {for (final p in ports) p.service};
  final names = {...publishing, ...services.keys, ...stable}.toList()..sort();
  final b = StringBuffer()
    ..writeln('# Written by podship: the $color color of $composeProject.')
    ..writeln('services:');
  for (final s in names) {
    final svc = services[s];
    final lines = <String>[];
    if (stable.contains(s)) {
      // Never in a color: the base project runs it. If someone names it
      // explicitly, it gets no volumes and no ports.
      lines
        ..add('    profiles: [${jsonEncode(stableProfile)}]')
        ..add('    ports: !reset []')
        ..add('    volumes: !reset []');
    } else {
      if (publishing.contains(s)) lines.add('    ports: !reset []');
      final deps = svc?.dependsOn ?? const {};
      if (deps.keys.any(stable.contains)) {
        final kept = {
          for (final d in deps.entries)
            if (!stable.contains(d.key)) d.key: d.value,
        };
        lines.add(
          kept.isEmpty
              ? '    depends_on: !reset {}'
              : '    depends_on: !override ${jsonEncode(kept)}',
        );
      }
      if (publishing.contains(s) && svc?.networkMode == null) {
        lines
          ..add('    networks:')
          ..add('      default: {}')
          ..add('      ${jsonEncode(net)}:')
          ..add('        aliases: [${jsonEncode('$color-$s')}]');
      }
    }
    if (lines.isEmpty) continue;
    b.writeln('  ${jsonEncode(s)}:');
    lines.forEach(b.writeln);
  }
  b.writeln('networks:');
  if (stable.isNotEmpty) {
    b
      ..writeln('  default:')
      ..writeln('    name: ${jsonEncode(colorNetwork(composeProject, color))}')
      ..writeln('    external: true');
  }
  b
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

/// Shell: the stable services of the base project [composeProject] join
/// the network of the compose project in `$proj` (a color), with their
/// service name as alias. Idempotent; the network is created when missing.
/// Used by every `compose.sh` of a color and by the start of a color, so a
/// recreated stable container joins again.
String stableJoinScript(String composeProject, List<String> stable) {
  if (stable.isEmpty) return '';
  final b = StringBuffer()
    ..writeln('case "\$proj" in')
    ..writeln(
      '  ${shq(colorProject(composeProject, 'blue'))}|${shq(colorProject(composeProject, 'green'))})',
    )
    ..writeln('    net="\$proj-net"')
    ..writeln(
      '    docker network inspect "\$net" >/dev/null 2>&1 || docker network create "\$net" >/dev/null 2>&1 || docker network inspect "\$net" >/dev/null',
    );
  for (final s in stable) {
    b
      ..writeln(
        '    for c in \$(docker ps -q --filter label=com.docker.compose.project=${shq(composeProject)} --filter label=com.docker.compose.service=${shq(s)}); do',
      )
      ..writeln(
        '      docker network connect --alias ${shq(s)} "\$net" "\$c" >/dev/null 2>&1 || true',
      )
      ..writeln('    done');
  }
  b
    ..writeln('    ;;')
    ..writeln('esac');
  return b.toString();
}

/// Shell: one public check of the new color, from inside container `$c`,
/// before it takes traffic. The request goes to [port] in the container
/// with the check's Host header; busybox `wget -S` gives the status and
/// the headers.
String preflightCheckScript(PublicCheck c, int port, String color) {
  final u = Uri.parse(c.url);
  final path = u.hasQuery ? '${u.path}?${u.query}' : u.path;
  final url = 'http://127.0.0.1:$port${path.isEmpty ? '/' : path}';
  final post = c.method.toUpperCase() == 'POST' ? " --post-data=''" : '';
  final what = shq('${c.method.toUpperCase()} ${u.host}$path');
  final b = StringBuffer()
    ..writeln('ok=; for i in 1 2 3 4 5; do')
    ..writeln(
      '  out=\$(docker exec "\$c" wget -S -O- -T 10 --header ${shq('Host: ${u.host}')}$post ${shq(url)} 2>&1 || true)',
    )
    ..writeln(
      "  st=\$(printf '%s\\n' \"\$out\" | sed -n 's/^ *HTTP\\/[0-9.]* \\([0-9][0-9][0-9]\\).*/\\1/p' | tail -1)",
    );
  final conds = <String>[
    if (c.status.isEmpty)
      'case "\$st" in 2??) true;; *) false;; esac'
    else
      'case " ${c.status.join(' ')} " in *" \$st "*) true;; *) false;; esac',
    if (c.contentType != null)
      "printf '%s\\n' \"\$out\" | grep -qi ${shq('^ *content-type: *${c.contentType}')}",
    if (c.contains != null)
      "printf '%s\\n' \"\$out\" | grep -qF -- ${shq(c.contains!)}",
  ];
  b
    ..writeln('  if ${conds.join(' && ')}; then ok=1; break; fi; sleep 2')
    ..writeln('done')
    ..writeln(
      '[ -n "\$ok" ] || { echo "$color fails the public check "$what" (status \$st):" >&2; printf \'%s\\n\' "\$out" | head -20 >&2; exit 1; }',
    )
    ..writeln('echo "$color passes "$what" (\$st)"');
  return b.toString();
}

/// Starts release [id] as [color], writes its override, and waits until its
/// front service answers [healthPaths] and passes [checks] inside its
/// container. With [stable] services, the base project runs them (never
/// recreated here) and they join the color's network first. [migrate] is a
/// one-off command run in the color before it starts (maintenance
/// migrations).
String startColorScript({
  required EnvLayout l,
  required String composeProject,
  required String id,
  required String color,
  required String override,
  required String serverService,
  required int serverPort,
  required List<String> healthPaths,
  List<String> stable = const [],
  List<PublicCheck> checks = const [],
  String? migrate,
  int waitSeconds = 180,
}) {
  final proj = colorProject(composeProject, color);
  final file = '${l.release(id)}/.podship/bg-$proj.yml';
  final compose = shq(l.composeSh(id));
  final b = StringBuffer()
    ..writeln(
      'docker network inspect ${frontNetwork(composeProject)} >/dev/null 2>&1 || docker network create ${frontNetwork(composeProject)} >/dev/null',
    );
  if (stable.isNotEmpty) {
    final names = stable.map(shq).join(' ');
    b
      ..writeln(
        '# The stable services run in the base project; never recreated by a blue/green deploy.',
      )
      ..writeln(
        'PODSHIP_COMPOSE_PROJECT=${shq(composeProject)} $compose up -d --no-build --no-recreate --wait $names',
      )
      ..writeln('proj=${shq(proj)}')
      ..write(stableJoinScript(composeProject, stable));
  }
  b
    ..write(writeFile(file, override))
    ..writeln(
      'svcs=\$(PODSHIP_COMPOSE_PROJECT=$proj $compose config --services)',
    );
  for (final s in stable) {
    b.writeln(
      "if printf '%s\\n' \"\$svcs\" | grep -qx ${shq(s)}; then echo \"blue/green: the stable service $s would run in $proj; stopping\" >&2; exit 1; fi",
    );
  }
  if (migrate != null) {
    b.writeln('PODSHIP_COMPOSE_PROJECT=$proj $compose $migrate');
  }
  b
    ..writeln(
      'PODSHIP_COMPOSE_PROJECT=$proj $compose up -d --no-build --remove-orphans',
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
        '  if docker exec "\$c" wget -qO- -T 5 ${shq('http://127.0.0.1:$serverPort$h')} >/dev/null 2>&1; then ok=1; break; fi; sleep 1',
      )
      ..writeln('done')
      ..writeln(
        '[ -n "\$ok" ] || { echo "$color does not answer $h" >&2; docker logs --tail 40 "\$c" >&2; exit 1; }',
      )
      ..writeln('echo "$color answers $h"');
  }
  for (final c in checks) {
    b.write(preflightCheckScript(c, serverPort, color));
  }
  return b.toString();
}

/// Shell: stops the running containers of [services] in compose project
/// [project] with a [timeout] in seconds (all of them when [services] is
/// empty).
String stopServicesScript(
  String project,
  List<String> services,
  int timeout, {
  String indent = '',
}) {
  if (services.isEmpty) {
    return '${indent}ids=\$(docker ps -q --filter label=com.docker.compose.project=$project)\n'
        '$indent[ -z "\$ids" ] || docker stop -t $timeout \$ids >/dev/null\n';
  }
  final b = StringBuffer();
  b.writeln('${indent}ids=');
  for (final s in services) {
    b.writeln(
      '${indent}ids="\$ids \$(docker ps -q --filter label=com.docker.compose.project=$project --filter label=com.docker.compose.service=${shq(s)})"',
    );
  }
  b.writeln(
    '$indent[ -z "\$(echo \$ids)" ] || docker stop -t $timeout \$ids >/dev/null',
  );
  return b.toString();
}

/// Points the front at [color] (starting the front the first time, after
/// [stopBase] frees the ports; [afterBase] runs after it starts) and
/// records it.
String flipScript({
  required EnvLayout l,
  required String composeProject,
  required String color,
  required List<PublishedPort> ports,
  String stopBase = '',
  String afterBase = '',
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
$afterBase fi
echo ${colorProject(composeProject, color)} > ${shq('${l.state}/active-project')}
echo "front → $color"
''';
}

/// Stops the containers of the color that no longer takes traffic (kept,
/// not removed, so a rollback starts it fast): first the services that
/// publish ports ([front]; nginx quits gracefully and gets [drainSeconds]
/// for open requests and streams), then the rest ([graceSeconds]).
String stopColorScript(
  String composeProject,
  String color, {
  List<String> front = const [],
  int drainSeconds = 30,
  int graceSeconds = 30,
}) {
  final proj = colorProject(composeProject, color);
  return '${front.isEmpty ? '' : stopServicesScript(proj, front, drainSeconds)}'
      '${stopServicesScript(proj, const [], graceSeconds)}'
      'echo "stopped $proj"\n';
}

/// The first blue/green deploy: the base project (no color) holds the
/// ports. Its services that publish them ([front]) stop right before the
/// front starts (a second or two); without [front], every service but the
/// [stable] ones.
String stopBaseScript(
  String composeProject, {
  List<String> front = const [],
  List<String> stable = const [],
}) {
  if (front.isNotEmpty) {
    return stopServicesScript(composeProject, front, 5, indent: '  ');
  }
  return stopBaseRestScript(composeProject, stable: stable, timeout: 30);
}

/// After the front took the ports: the base project's other services stop,
/// except the [stable] ones.
String stopBaseRestScript(
  String composeProject, {
  List<String> stable = const [],
  int timeout = 30,
}) {
  final b = StringBuffer()
    ..writeln(
      '  for c in \$(docker ps -q --filter label=com.docker.compose.project=$composeProject); do',
    )
    ..writeln(
      '    s=\$(docker inspect -f \'{{index .Config.Labels "com.docker.compose.service"}}\' "\$c")',
    );
  if (stable.isNotEmpty) {
    b.writeln('    case " ${stable.join(' ')} " in *" \$s "*) continue;; esac');
  }
  b
    ..writeln('    docker stop -t $timeout "\$c" >/dev/null')
    ..writeln('  done');
  return b.toString();
}

/// Shell: leaves blue/green for an in-place switch (`switch: in_place`, or
/// `--allow-destructive-migrations`): the front and the colors go, so the
/// base project can take the ports again. Nothing when no color is active.
String leaveBlueGreenScript(EnvLayout l, String composeProject) =>
    '''
if [ -f ${shq('${l.state}/active-project')} ]; then
  docker rm -f ${frontContainer(composeProject)} >/dev/null 2>&1 || true
  for p in ${colorProject(composeProject, 'blue')} ${colorProject(composeProject, 'green')}; do
    ids=\$(docker ps -aq --filter label=com.docker.compose.project=\$p)
    [ -z "\$ids" ] || { docker stop -t 10 \$ids >/dev/null; docker rm \$ids >/dev/null; }
  done
  rm -f ${shq('${l.state}/active-project')}
  echo "left blue/green: the base project takes the ports"
fi
''';

/// The steps of a blue/green switch to release [id], and the recovery.
/// The color is read from the server when the step runs. [migrate] runs
/// the maintenance migrations in the new color before it starts.
({Step start, Step stopOld, List<Step> recovery}) blueGreenSteps(
  Ctx ctx,
  ResolvedEnv r,
  String id, {
  required String? old,
  required String action,
  bool migrate = false,
  bool preflight = true,
}) {
  final env = r.env;
  final l = EnvLayout(env);
  final cp = env.composeProject;
  final stable = env.stableServices;
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

  List<String> frontServices() => {for (final p in ports) p.service}.toList();

  final start = ActionStep(
    'Start $id next to ${old ?? 'nothing'} (blue/green)',
    'compose project $cp-blue or -green without host ports'
        '${stable.isEmpty ? '' : '; ${stable.join(', ')} stay in $cp and join the color'}'
        '${migrate ? '; migrations in the new color' : ''}'
        '; wait for /health and /readyz and the public checks inside it; flip the front ($cp-front, nginx stream); record',
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
      for (final s in stable) {
        if (!cfg.services.containsKey(s)) {
          throw Aborted(
            'blue/green: the stable service "$s" is not in the compose files',
          );
        }
      }
      final stablePorts = ports.where((p) => stable.contains(p.service));
      if (stablePorts.isNotEmpty) {
        throw Aborted(
          'blue/green: a stable service publishes a port (${stablePorts.join(', ')}); '
          'only a color may publish the environment\'s ports',
        );
      }
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
            services: cfg.services,
            stable: stable,
          ),
          serverService: hp.service,
          serverPort: hp.target,
          healthPaths: [health.path, ?readiness],
          stable: stable,
          checks: preflight
              ? [
                  for (final c in env.health.publicChecks)
                    c.withUrl(r.sub(c.url)),
                ]
              : const [],
          migrate: migrate
              ? 'run --rm --no-deps -e SERVERPOD_SERVER_ROLE=maintenance '
                    '-e SERVERPOD_APPLY_MIGRATIONS=true ${env.serverService}'
              : null,
        ),
      );
      await stream(
        flipScript(
          l: l,
          composeProject: cp,
          color: color!,
          ports: ports,
          stopBase: active!.isEmpty
              ? stopBaseScript(cp, front: frontServices(), stable: stable)
              : '',
          afterBase: active!.isEmpty
              ? stopBaseRestScript(cp, stable: stable)
              : '',
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
    'the services that publish ports first (graceful, ${env.blueGreen.drainSeconds} s for open requests and streams), then the rest; kept for a fast rollback',
    () async {
      if (active == null || active!.isEmpty) return;
      await stream(
        stopColorScript(
          cp,
          active == '$cp-blue' ? 'blue' : 'green',
          front: frontServices(),
          drainSeconds: env.blueGreen.drainSeconds,
          graceSeconds: env.serverpod.stopGraceSeconds,
        ),
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
        await stream(
          stopColorScript(
            cp,
            color!,
            front: frontServices(),
            drainSeconds: env.blueGreen.drainSeconds,
            graceSeconds: env.serverpod.stopGraceSeconds,
          ),
        );
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
