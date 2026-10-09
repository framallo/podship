// The server itself: bootstrap, shared Postgres, registry views, teardown.

import '../config/config.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import '../server/registry.dart';
import 'context.dart';
import 'resolve.dart';
import 'scripts.dart';

/// The bootstrap script. Idempotent: it only adds what is missing, and it
/// never removes firewall rules or packages.
String bootstrapScript(
  EnvConfig env, {
  bool caddy = false,
  bool firewall = true,
  String? deployUser,
}) =>
    '''
${portableHelpers}home=${shq(env.podshipHome)}
if [ "\$(uname -s)" = Darwin ]; then
  echo "macOS server: podship does not install packages here."
  for t in docker rsync curl; do command -v \$t >/dev/null && echo "  ok  \$t" || echo "  MISSING \$t"; done
  docker compose version >/dev/null 2>&1 && echo "  ok  docker compose" || echo "  MISSING docker compose (Docker Desktop or colima)"
  command -v age >/dev/null && echo "  ok  age" || echo "  missing age (brew install age) — needed for encrypted backups"
  command -v zstd >/dev/null && echo "  ok  zstd" || echo "  missing zstd (brew install zstd) — or set backup.compression: gzip"
  mkdir -p "\$home/lib" "\$home/etc" "\$home/log" ${shq(env.dir)}
  chmod 700 "\$home/etc"
  exit 0
fi
[ "\$(id -u)" = 0 ] || { echo "run bootstrap as root (ssh as root, or a user with sudo)" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
command -v apt-get >/dev/null || { echo "only Debian and Ubuntu are supported by bootstrap" >&2; exit 1; }
need=""
for t in curl rsync age zstd; do command -v \$t >/dev/null || need="\$need \$t"; done
if [ -n "\$need" ]; then
  echo "installing:\$need"
  apt-get update -qq && apt-get install -y -qq \$need
fi
if ! command -v docker >/dev/null; then
  echo "installing Docker (get.docker.com)"
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || apt-get install -y -qq docker-compose-plugin
systemctl enable --now docker >/dev/null
${caddy ? '''
if ! command -v caddy >/dev/null; then
  echo "installing Caddy"
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https gnupg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy
fi
mkdir -p /etc/caddy/podship
grep -q 'import /etc/caddy/podship/\\*.caddy' /etc/caddy/Caddyfile || echo 'import /etc/caddy/podship/*.caddy' >> /etc/caddy/Caddyfile
systemctl enable --now caddy >/dev/null
''' : ''}
${firewall ? '''
if command -v ufw >/dev/null; then
  ufw allow OpenSSH >/dev/null
  ${caddy ? 'ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null' : 'true'}
  if ufw status | grep -q inactive; then ufw --force enable; fi
  ufw status | head -3
fi
''' : ''}
${deployUser == null ? '' : '''
if ! id ${shq(deployUser)} >/dev/null 2>&1; then useradd -m -s /bin/bash ${shq(deployUser)}; fi
usermod -aG docker ${shq(deployUser)}
'''}
mkdir -p "\$home/lib" "\$home/etc" "\$home/log" ${shq(env.dir)}
chmod 700 "\$home/etc" ${shq(env.dir)}
docker image inspect python:3.12-alpine >/dev/null 2>&1 || docker pull -q python:3.12-alpine
echo "docker \$(docker version --format '{{.Server.Version}}'), compose \$(docker compose version --short)"
echo "bootstrap done"
''';

/// Starts the shared Postgres (once per server) and creates the database
/// and role of [r]. Returns the role password through stdout as
/// `PODSHIP_DB_PASSWORD=…`; the caller stores it as a secret and never
/// prints it.
String sharedDbScript(EnvConfig env) {
  final db = env.database;
  final c = DatabaseConfig.sharedContainer, net = DatabaseConfig.sharedNetwork;
  final adminFile = '${env.etcDir}/shared-postgres.env';
  return '''
docker network inspect $net >/dev/null 2>&1 || docker network create $net >/dev/null
if [ ! -f ${shq(adminFile)} ]; then
  umask 077; echo "POSTGRES_PASSWORD=\$(head -c 32 /dev/urandom | base64 | tr -d '=+/')" > ${shq(adminFile)}
fi
if [ -z "\$(docker ps -q --filter name=^$c\$)" ]; then
  docker rm -f $c >/dev/null 2>&1 || true
  docker run -d --name $c --restart unless-stopped --network $net \\
    --env-file ${shq(adminFile)} -v podship-postgres-data:/var/lib/postgresql/data \\
    --health-cmd "pg_isready -U postgres" postgres:16-alpine >/dev/null
  for i in \$(seq 60); do docker exec $c pg_isready -q -U postgres -h 127.0.0.1 && break; sleep 1; done
fi
pw=\$(head -c 24 /dev/urandom | base64 | tr -d '=+/')
if docker exec $c psql -U postgres -Atqc "select 1 from pg_roles where rolname = '${db.user}'" | grep -q 1; then
  docker exec $c psql -U postgres -q -c "alter role \\"${db.user}\\" password '\$pw'"
else
  docker exec $c psql -U postgres -q -c "create role \\"${db.user}\\" login password '\$pw'"
fi
docker exec $c psql -U postgres -Atqc "select 1 from pg_database where datname = '${db.name}'" | grep -q 1 ||
  docker exec $c psql -U postgres -q -c "create database \\"${db.name}\\" owner \\"${db.user}\\""
echo "PODSHIP_DB_PASSWORD=\$pw"
''';
}

/// The registry as a table.
List<String> registryTable(Registry reg) => [
  for (final e in reg.entries.values)
    '${e.key.padRight(32)} ${e.composeProject.padRight(26)} '
        '${e.ports.entries.map((x) => '${x.key}=${x.value}').join(',').padRight(34)} '
        '${e.domains.join(',')}  ${e.database}  ${e.backupSchedule ?? '-'}',
];

/// Plans `destroy`: stop and remove an environment completely.
Plan planDestroy(
  Ctx ctx,
  ResolvedEnv r,
  Registry reg,
  String regText, {
  required bool purgeBackups,
  required List<Step> domainSteps,
  required List<Step> scheduleSteps,
}) {
  final env = r.env;
  final l = EnvLayout(env);
  reg.remove(r.entry.key);
  return Plan('destroy ${ctx.config.project}/${env.name} on ${env.host}', [
    ...domainSteps,
    ...scheduleSteps,
    RemoteStep('Stop and remove containers, volumes and images', env.host, '''
${ctx.header(env)}if [ -x ${shq(l.currentComposeSh)} ]; then
  ${shq(l.currentComposeSh)} down --volumes --remove-orphans --timeout 20
else
  ids=\$(docker ps -aq --filter label=com.docker.compose.project=${shq(env.composeProject)})
  [ -n "\$ids" ] && docker rm -f \$ids
  vols=\$(docker volume ls -q --filter label=com.docker.compose.project=${shq(env.composeProject)})
  [ -n "\$vols" ] && docker volume rm \$vols
fi
for d in ${shq(l.releases)}/*/; do
  for img in \$(cat "\$d/.podship/images" 2>/dev/null); do docker image rm "\$img" >/dev/null 2>&1 || true; done
done
docker network rm ${shq('${env.composeProject}_default')} >/dev/null 2>&1 || true
rm -rf -- ${shq(env.dir)}
${purgeBackups && env.backup != null ? 'rm -rf -- ${shq(env.backup!.dir)}\n' : ''}rm -f ${env.backup == null ? '' : '${shq(backupConfPath(env))} ${shq(recipientsPath(env))}'}
'''),
    RegistryWriteStep(
      'Write the registry',
      env.host,
      env.registryPath,
      header: ctx.header(env),
      base: regText,
      mine: reg.render(),
    ),
  ]);
}
