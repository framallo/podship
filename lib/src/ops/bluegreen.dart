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
  // An empty `stream {}` passes `nginx -t`, and a reload then closes every
  // listener: the environment goes down.
  if (ports.isEmpty) {
    throw ArgumentError('the front of $color needs at least one port');
  }
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

/// Shell (compose.sh): when `$proj` is a color and the arguments name a
/// [stable] service (`up -d postgres`, `restart postgres`, `exec postgres
/// psql`, `logs postgres`), the command goes to the base project instead:
/// in a color, compose enables a profiled service when it is named, and
/// that would start a second, empty database next to the real one. Sets
/// `routed` (empty when not routed).
String stableRouteScript(String composeProject, List<String> stable) {
  final names = ' ${stable.join(' ')} ';
  final b = StringBuffer()..writeln('routed=');
  if (stable.isEmpty) return b.toString();
  b
    ..writeln('_podship_names_stable() {')
    ..writeln(r'  local sub= first= skip= a')
    ..writeln(r'  for a in "$@"; do')
    ..writeln(r'    if [ -n "$skip" ]; then skip=; continue; fi')
    ..writeln(r'    case "$a" in')
    ..writeln(r'      --*=*) continue;;')
    // Options whose value could be a service name (exec -u postgres).
    ..writeln(
      r'      -e|--env|-u|--user|-w|--workdir|--name|--entrypoint|-l|--label|-v|--volume|-p|--publish|--profile|--env-file|-f|--file|--project-directory) skip=1; continue;;',
    )
    ..writeln(r'      -*) continue;;')
    ..writeln('    esac')
    ..writeln(r'    if [ -z "$sub" ]; then sub=$a; continue; fi')
    ..writeln(r'    case "$sub" in')
    ..writeln('      exec|run)')
    ..writeln(r'        [ -z "$first" ] || continue; first=$a')
    ..writeln('        case ${shq(names)} in *" \$a "*) return 0;; esac;;')
    ..writeln(
      '      up|start|restart|stop|create|rm|kill|pull|logs|ps|top|pause|unpause|port|attach|wait|watch|events|images|cp)',
    )
    ..writeln('        case ${shq(names)} in *" \$a "*) return 0;; esac;;')
    ..writeln('    esac')
    ..writeln('  done')
    ..writeln('  return 1')
    ..writeln('}')
    ..writeln('case "\$proj" in')
    ..writeln(
      '  ${shq(colorProject(composeProject, 'blue'))}|${shq(colorProject(composeProject, 'green'))})',
    )
    ..writeln('    if _podship_names_stable "\$@"; then')
    ..writeln(
      '      echo "compose.sh: ${stable.join(', ')} run in the base project ${composeProject.replaceAll('"', '')}, not in \$proj" >&2',
    )
    ..writeln('      routed=\$proj; proj=${shq(composeProject)}')
    ..writeln('    fi;;')
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
      // busybox wget prints no headers and no body for a 4xx or 5xx: then
      // only the status counts here (the checks after the flip see all).
      "{ ! printf '%s\\n' \"\$out\" | grep -qi '^ *content-type:' || printf '%s\\n' \"\$out\" | grep -qi ${shq('^ *content-type: *${c.contentType}')}; }",
    if (c.contains != null)
      "{ case \"\$st\" in 2??) printf '%s\\n' \"\$out\" | grep -qF -- ${shq(c.contains!)};; *) true;; esac; }",
  ];
  b
    ..writeln('  if ${conds.join(' && ')}; then ok=1; break; fi; sleep 2')
    ..writeln('done')
    ..writeln(
      '[ -n "\$ok" ] || { echo "$color fails the public check "$what" (status \$st):" >&2; printf \'%s\\n\' "\$out" | grep -vi \'^ *set-cookie:\' | head -20 >&2; exit 1; }',
    )
    ..writeln('echo "$color passes "$what" (\$st)"');
  return b.toString();
}

/// Shell: finds the [service] container of compose [project] (as `$c`)
/// and waits until it answers each of [paths] on [port] from inside.
String healthWaitScript({
  required String project,
  required String label,
  required String service,
  required int port,
  required List<String> paths,
  int seconds = 180,
}) {
  final b = StringBuffer()
    ..writeln(
      'c=\$(docker ps -q --filter label=com.docker.compose.project=$project --filter label=com.docker.compose.service=$service | head -1)',
    )
    ..writeln(
      '[ -n "\$c" ] || { echo "no $service container in $project" >&2; exit 1; }',
    );
  for (final h in paths) {
    b
      ..writeln('ok=; for i in \$(seq $seconds); do')
      ..writeln(
        '  if docker exec "\$c" wget -qO- -T 5 ${shq('http://127.0.0.1:$port$h')} >/dev/null 2>&1; then ok=1; break; fi; sleep 1',
      )
      ..writeln('done')
      ..writeln(
        '[ -n "\$ok" ] || { echo "$label does not answer $h" >&2; docker logs --tail 40 "\$c" >&2; exit 1; }',
      )
      ..writeln('echo "$label answers $h"');
  }
  return b.toString();
}

/// Shell: warns when a running stable service differs from the compose
/// files of the release (an image bump, new settings): a blue/green deploy
/// never recreates it, so the change waits for `podship restart <service>`.
String stableDriftScript(
  String composeProject,
  String compose,
  List<String> stable,
) {
  final b = StringBuffer();
  for (final s in stable) {
    b
      ..writeln(
        'want=\$(PODSHIP_COMPOSE_PROJECT=${shq(composeProject)} $compose config --hash ${shq(s)} 2>/dev/null | awk \'{print \$2}\' || true)',
      )
      ..writeln(
        'sc=\$(docker ps -q --filter label=com.docker.compose.project=${shq(composeProject)} --filter label=com.docker.compose.service=${shq(s)} | head -1); have=',
      )
      ..writeln(
        '[ -z "\$sc" ] || have=\$(docker inspect -f \'{{index .Config.Labels "com.docker.compose.config-hash"}}\' "\$sc" 2>/dev/null || true)',
      )
      ..writeln(
        'if [ -n "\$want" ] && [ -n "\$have" ] && [ "\$want" != "\$have" ]; then echo "WARNING: $s changed in the compose files (image or settings), but blue/green keeps the running one; apply it with: podship restart $s (a short database outage)" >&2; fi',
      );
  }
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
      ..write(stableDriftScript(composeProject, compose, stable))
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
    ..write(
      healthWaitScript(
        project: proj,
        label: color,
        service: serverService,
        port: serverPort,
        paths: healthPaths,
        seconds: waitSeconds,
      ),
    );
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
  // A running front: the new config is tested before it replaces the one
  // nginx runs, so the file on disk always names the color that serves.
  // active-project follows the reload; a crash in between is repaired at
  // the next start (frontColorScript).
  return '''
if docker container inspect $front >/dev/null 2>&1; then
${writeFile('${l.state}/front/next.conf', frontConf(ports, color))}  docker exec $front nginx -t -q -c /etc/podship-front/next.conf
  mv -f ${shq('${l.state}/front/next.conf')} ${shq(conf)}
  docker exec $front nginx -s reload -c /etc/podship-front/nginx.conf
else
${writeFile(conf, frontConf(ports, color))}  docker image inspect nginx:1.27-alpine >/dev/null 2>&1 || docker pull -q nginx:1.27-alpine >/dev/null
$stopBase  docker run -d --name $front --restart unless-stopped --label podship.front=$composeProject --network ${frontNetwork(composeProject)} $publish -v ${shq('${l.state}/front')}:/etc/podship-front:ro nginx:1.27-alpine nginx -c /etc/podship-front/nginx.conf -g 'daemon off;' >/dev/null
$afterBase fi
echo ${colorProject(composeProject, color)} > ${shq('${l.state}/active-project')}
echo "front → $color"
''';
}

/// Shell: prints the color the front serves (from its config), or nothing
/// when no front container runs.
String frontColorScript(EnvLayout l, String composeProject) =>
    'docker container inspect ${frontContainer(composeProject)} >/dev/null 2>&1 && '
    "sed -n 's/^# Written by podship: the front of the \\([a-z]*\\) color\\.\$/\\1/p' "
    '${shq('${l.state}/front/nginx.conf')} 2>/dev/null || true\n';

/// The compose project with the traffic: the front's config wins over
/// active-project, which is written after the reload. Throws when a color
/// is recorded but no front runs.
String activeProject({
  required String composeProject,
  required String recorded,
  required String frontColor,
}) {
  if (frontColor.isNotEmpty) return colorProject(composeProject, frontColor);
  if (recorded.isNotEmpty) {
    throw Aborted(
      'blue/green: $recorded is recorded as active, but the front '
      '(${frontContainer(composeProject)}) does not run. Start it again '
      '(docker start ${frontContainer(composeProject)}) or leave blue/green '
      'with switch: in_place',
    );
  }
  return '';
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
/// front starts, with 1 s to quit: nginx keeps the port until it exits,
/// and an open WebSocket keeps a graceful quit waiting (staging
/// 2026-11-14: 5 s of 502 with a 5 s timeout). Without [front], every
/// service but the [stable] ones.
String stopBaseScript(
  String composeProject, {
  List<String> front = const [],
  List<String> stable = const [],
}) {
  if (front.isNotEmpty) {
    return stopServicesScript(composeProject, front, 1, indent: '  ');
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
if [ -f ${shq('${l.state}/active-project')} ] || docker container inspect ${frontContainer(composeProject)} >/dev/null 2>&1; then
  docker rm -f ${frontContainer(composeProject)} >/dev/null 2>&1 || true
  for p in ${colorProject(composeProject, 'blue')} ${colorProject(composeProject, 'green')}; do
    ids=\$(docker ps -aq --filter label=com.docker.compose.project=\$p)
    [ -z "\$ids" ] || { docker stop -t 10 \$ids >/dev/null; docker rm \$ids >/dev/null; }
  done
  for n in ${colorNetwork(composeProject, 'blue')} ${colorNetwork(composeProject, 'green')} ${frontNetwork(composeProject)}; do
    docker network inspect "\$n" >/dev/null 2>&1 || continue
    # Running endpoints, and every container of the base project: a stopped
    # container is not listed, but keeps the network in its config and would
    # not start once the network is gone (staging 2026-11-14).
    for c in \$(docker network inspect -f '{{range \$k, \$v := .Containers}}{{\$k}} {{end}}' "\$n") \$(docker ps -aq --filter label=com.docker.compose.project=$composeProject); do
      docker network disconnect -f "\$n" "\$c" >/dev/null 2>&1 || true
    done
    docker network rm "\$n" >/dev/null 2>&1 || true
  done
  rm -rf ${shq('${l.state}/front')}
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
  PublishedPort? served; // the service that answers /health
  var healthPaths = const <String>[];
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
      final recorded = (await q(
        'cat ${shq('${l.state}/active-project')} 2>/dev/null || true\n',
      )).trim();
      final frontColor = (await q(frontColorScript(l, cp))).trim();
      active = activeProject(
        composeProject: cp,
        recorded: recorded,
        frontColor: frontColor,
      );
      if (active != recorded) {
        ctx.log.warn(
          'blue/green: active-project said "$recorded", the front serves $active; recording $active',
        );
        await stream(
          'echo ${shq(active!)} > ${shq('${l.state}/active-project')}\n',
        );
      }
      // [color] and [ports] are set only right before the new color
      // starts: a failure before that started nothing, and the recovery
      // then leaves the front alone (an empty port list would write a
      // front with no listener).
      final next = otherColor(
        active == '$cp-blue'
            ? 'blue'
            : active == '$cp-green'
            ? 'green'
            : null,
      );
      final proj = colorProject(cp, next);
      // A release made by an in-place deploy (a rollback target from before
      // blue/green) has a compose.sh that ignores PODSHIP_COMPOSE_PROJECT:
      // it gets the blue/green one.
      final sh = l.composeSh(id);
      final hasBg = (await q(
        'grep -q PODSHIP_COMPOSE_PROJECT ${shq(sh)} && echo yes || echo no\n',
      )).trim();
      if (hasBg != 'yes') {
        final files = (await q(
          'cat ${shq('${l.release(id)}/.podship/compose-files')}\n',
        )).split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
        if (files.isEmpty) {
          throw Aborted('blue/green: release $id lists no compose files');
        }
        await stream(
          '${writeFile(sh, composeSh(composeProject: cp, releaseDir: l.release(id), composeFiles: files, ports: r.ports, remotePath: env.remotePath, blueGreenState: l.state, stable: stable))}'
          'chmod 755 ${shq(sh)}\n'
          'echo "compose.sh of $id: blue/green"\n',
        );
      }
      final cfg = parseComposeConfig(
        await q(
          'PODSHIP_COMPOSE_PROJECT=$cp ${shq(l.composeSh(id))} config --format json\n',
        ),
      );
      final cfgPorts = cfg.ports;
      for (final s in stable) {
        if (!cfg.services.containsKey(s)) {
          throw Aborted(
            'blue/green: the stable service "$s" is not in the compose files',
          );
        }
      }
      final stablePorts = cfgPorts.where((p) => stable.contains(p.service));
      if (stablePorts.isNotEmpty) {
        throw Aborted(
          'blue/green: a stable service publishes a port (${stablePorts.join(', ')}); '
          'only a color may publish the environment\'s ports',
        );
      }
      final health = Uri.parse(r.healthUrl);
      final hp = cfgPorts.where((p) => p.published == health.port).firstOrNull;
      if (hp == null) {
        throw Aborted(
          'blue/green: no service publishes port ${health.port} of ${r.healthUrl}',
        );
      }
      final readiness = r.readinessUrl == null
          ? null
          : Uri.parse(r.readinessUrl!).path;
      ports = cfgPorts;
      served = hp;
      healthPaths = [health.path, ?readiness];
      color = next;
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
          healthPaths: healthPaths,
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
        if (color == null || ports.isEmpty) return;
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
            // The old color answers before it gets the traffic back.
            // If it does not within 120 s, it gets it anyway: the new color
            // already failed.
            '(\n${healthWaitScript(project: active!, label: back, service: served!.service, port: served!.target, paths: healthPaths, seconds: 120)}) || echo "$back is not healthy yet; flipping back anyway" >&2\n'
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
