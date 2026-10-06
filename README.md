# podship

Deploy, back up and roll back [Serverpod](https://serverpod.dev) projects on your own servers, with production and staging.

podship is a command-line tool. It talks to your servers over ssh and runs everything with Docker Compose. Nothing runs on a server except Docker, a few bash scripts, and systemd timers (or launchd on a Mac).

```
podship deploy --env staging
podship promote staging production
podship rollback --env production
podship backup now --env production
```

## What it does

- **Releases.** Each deploy is a release with an id like `20261006-170512-a0dc2b0` (UTC time and git commit). The server keeps the last few releases, with their files and their images. `rollback` switches back in seconds, with no build.
- **Health checks and automatic rollback.** After the switch, podship checks a health URL on the server, and optionally the public URL. If the check fails, it switches back to the previous release by itself.
- **Environments.** `production`, `staging` or any name. Each one has its own compose project, network, database, volumes, ports, domain and secrets. They can share a server or use different servers.
- **Many projects on one server.** A registry on each server records every project and environment. podship refuses a second user of a directory, compose project, port, domain or backup slot. It gives free ports and backup times to environments that ask for `auto`.
- **Secrets on the server only.** `.env` and Serverpod's `passwords.yaml` live on the server. podship edits them over ssh stdin. It never prints a secret value and never puts one in a command line.
- **Backups.** `pg_dump -Fc` of the database, archives of Docker volumes (SQLite files copied with SQLite's backup API), row counts, checksums, and an encrypted copy that you decrypt with your SSH key. A daily schedule, retention, a restore drill in a throwaway container, a restore that renames the old database instead of dropping it, and an off-site pull to your machine.
- **Domains.** Routes through a Cloudflare Tunnel, or Caddy with automatic Let's Encrypt certificates.
- **Dry runs.** Every command that changes something takes `--dry-run` and prints its plan.

## Install

```
dart pub global activate --source git https://github.com/framallo/podship
```

This puts `podship` in `~/.pub-cache/bin`. Add that folder to your `PATH` if it is not there.

On your machine you need `git`, `ssh`, `rsync` and `bash`, `flutter` if you ship Flutter web apps, and `age` to check off-site backups. Servers need Docker with the compose plugin, `curl` and `rsync`, and for backups `age` and `zstd` (or `compression: gzip`). `podship server bootstrap` installs them on Debian and Ubuntu.

## Quick start

```
cd my_project              # the folder that holds my_project_server/
podship init               # writes podship.yaml, deploy/docker-compose.yml, and a Dockerfile if missing
$EDITOR podship.yaml       # set host: for production and staging
podship doctor             # checks tools, ssh, Docker, disk, ports and DNS
podship launch --env staging
```

`launch` runs, in order: `server bootstrap`, `link`, `secret init`, `db provision` (shared database only), `deploy`, `domain add` and `backup schedule`. You can run each one by itself.

## Commands

Commands that can destroy data or stop production default to `--env staging`. For production you must write `--env production`. `--yes` answers confirmations (for CI). Restores, `db wipe` and `destroy` also ask you to type the project name; in CI, pass `--confirm <project>`.

| Command | What it does |
|---|---|
| `init` | Writes `podship.yaml`, a compose file, `.podshipignore` and a Dockerfile. Finds the server package and the Flutter web apps. |
| `launch` | The first deploy of an environment, from bootstrap to backup schedule. |
| `doctor` | Checks local tools, ssh, Docker and compose on each server, disk, ports, the registry and DNS. |
| `link` | Registers the environment in the server registry: ports, domains, database and backup slot. |
| `deploy` | Builds Flutter web locally, uploads the files, builds images on the server, backs up the database, switches, checks health, rolls back on failure, and prunes old releases. Flags: `--ref`, `--worktree`, `--skip-web`, `--skip-backup`, `--skip-hooks`, `--no-public-check`. |
| `rollback` | Switches to the previous release, or to `--to <release>`. Code only. `--with-db <stamp>` also restores that backup first. |
| `promote <from> <to>` | Runs on `<to>` the exact release of `<from>`: the same files and the same images, with no build. Between servers with different CPU architectures it stops and tells you to deploy the same commit instead. |
| `restart [service…]` | Recreates the containers of the current release, for example after `env set`. |
| `adopt` | Records a setup that already runs (started by hand or by scripts) as a release, without restarting it, so `rollback` can come back to it. |
| `status` | Current and previous releases, containers, health, disk and recent history. `--watch`. |
| `logs` | Container logs. `--service`, `--since`, `--until`, `--tail`, `--follow`, `--timestamps`. |
| `releases list`, `releases history` | The releases on the server; the deploys, rollbacks and promotions. |
| `env list/get/set/unset` | Plain variables in the environment's `.env`. |
| `secret init/list/set/unset/copy` | Secrets in `.env` and `passwords.yaml`. `set` reads the value from stdin, a hidden prompt, `--from-file` or `--generate`. `copy --from <env>` copies values between environments without showing them. `init` creates both files with fresh random values. |
| `backup now/list/drill/restore/schedule/pull` | See [Backups](#backups). |
| `db connect` | `psql` on the environment database. |
| `db migrate status` | The applied Serverpod migrations, against the newest one in the current release. |
| `db user list/create/reset-password/delete` | Database roles for people and tools. The password is printed once. |
| `db provision` | Shared-Postgres mode: starts `podship-postgres` once per server and creates the environment's database and role. |
| `db wipe` | An empty database. The old one is renamed, not dropped. |
| `tunnel` | Forwards a local port to a service port that is not published, like Serverpod Insights (`--service server --port 8081`) or Postgres (`--service postgres --port 5432`). |
| `domain add/remove/list` | Routes domains through a Cloudflare Tunnel or Caddy, and prints the DNS record you need. |
| `server bootstrap` | Installs Docker, compose, age, zstd, the firewall rules and podship's folders. Safe to run again. |
| `server status` | Every project on the server: registry, containers, CPU and memory, disk. |
| `projects list` | The server registry. |
| `access list/add/remove` | Per-person ssh keys on a server, marked `podship:<name>` in `authorized_keys`. |
| `ci setup` | Creates an ssh deploy key for CI, gives it access, and prints a GitHub Actions workflow. |
| `destroy` | Removes an environment: containers, volumes, images, files, routes, schedule and registry entry. `--purge-backups` also deletes its backups. |

Global options: `--project-dir <dir>` (`-C`), `--ssh-key <file>`, `--yes`, `--verbose`, `--quiet`.

## podship.yaml

The file lives in the project root and is committed. It has no secrets.

```yaml
project: shop                       # destructive commands ask you to type this
server_package: shop_server

build:
  source: git                       # git: export the commit; worktree: the files as they are
  ref: main
  flutter_web:
    - name: app
      path: shop_flutter
      output: shop_server/web/app
      base_href: /app/
  pre_deploy: []                    # local shell commands, in the export, before the upload
  post_deploy: []                   # local shell commands after a healthy deploy
  files:                            # gitignore syntax, applied last
    - "!shop_server/web/app/**"     # ship the web build even though .gitignore excludes it
    - shop_flutter/**               # the server image does not need the app sources

compose:
  files: [deploy/docker-compose.yml]
  build_contexts: {}                # service: /absolute/path on the server, for code outside this repo
  remote_pre_build: []              # shell commands on the server before the build

environments:
  production:
    host: shop-vps                  # an ssh destination; ~/.ssh/config aliases work
    dir: /srv/shop
    ports: {api: auto, web: auto}   # or numbers
    health:
      url: http://127.0.0.1:{port:web}/health   # fetched on the server
      public_url: https://shop.example.com/health
    secrets:
      template: .env.example        # used by `secret init`
      generate: [SHOP_MASTER_KEY]   # filled with random values by `secret init`
      database_password_env: POSTGRES_PASSWORD
    database: {name: shop}          # mode: per_env (default) or shared
    migrations: on_start            # on_start, maintenance or none
    releases: {keep: 5}
    backup:
      recipients: [~/.ssh/id_ed25519.pub]
      volumes:
        - {name: uploads, volume: shop_uploads}
      offsite: {dir: ~/Backups/shop}
    proxy: {kind: caddy}
    domains:
      - host: shop.example.com
        routes:
          - {path: "^/(api|v1)/", port: api}
          - {port: web}
  staging:
    host: shop-vps
    dir: /srv/shop-staging
    # …
```

Only `project` is required at the top, and `host`, `dir` and `health.url` in each environment. Other keys:

- `compose_project` (default: the project name for `production`, `<project>-<env>` for the others), `compose_files` (extra compose files for this environment only), `run_mode`, `plain_env` (variables whose values may be printed), `remote_path` (added to the front of `PATH` on the server), `podship_home` (default `/srv/podship`), `server_service` (default `server`), per-environment `build_contexts` and `remote_pre_build`, and `scheduler` (`auto`, `systemd` or `launchd`).
- `health.fallback_urls` and `health.public_fallback_urls`: other URLs that also count as healthy, so a rollback to a release from before a health route moved still passes. `health.attempts`, and `health.interval` in seconds.
- `secrets.env_file` and `secrets.passwords_file` (relative to `dir`; default `shared/.env` and `shared/passwords.yaml`), `secrets.passwords_link` (where each release sees `passwords.yaml`), and `secrets.password_keys`.
- `backup.dir`, `unit`, `schedule` (a systemd `OnCalendar` value; empty means a free slot from the registry), `timezone`, `retention` (`days`, `weeks`, `months`), `compression` (`zstd` or `gzip`), `layout` (the `plain`, `encrypted`, `dump`, `counts` and `secrets` names), `stop_on_restore`, `drill.tables` and `drill.volatile` (globs), `offsite.identities`, `before_deploy`, and `replaces` (older schedule units to turn off).
- `proxy.kind` (`cloudflare_tunnel`, `caddy` or `none`), `proxy.config`, `proxy.service` and `proxy.tunnel_id`.

For compose files, podship exports `PODSHIP_PORT_<NAME>` for each port, so a compose file can publish `127.0.0.1:${PODSHIP_PORT_WEB}:8082`.

## Shipping files that are not Dart

A release ships the files of your project, selected like this:

1. With `source: git`, podship exports the commit with `git archive` into a temporary folder. Uncommitted changes do not ship, and the release id names a real commit. With `source: worktree` (or `deploy --worktree`), the files come from your folder as they are, and the release id ends in `-dirty` when there are uncommitted changes.
2. podship builds each Flutter web app into its `output` folder, then runs the `pre_deploy` commands.
3. Every `.gitignore` and `.podshipignore` applies: parents before children, and `.gitignore` before `.podshipignore` in the same folder.
4. The `build.files` rules apply last.

The rules use gitignore syntax. `*` stays inside a folder, `**` crosses folders, a `/` at the start or in the middle anchors the pattern to the folder of its file, a trailing `/` matches folders only, and `!` includes again. The last matching rule wins. A rule that excludes a folder excludes the files in it, and a later rule can include one of those files again: for example `!shop_server/web/app/**` after the `.gitignore` line `web/app`.

Some files never ship, whatever the rules say: `.git/`, `.dart_tool/`, `.env`, `.env.*` (but `.example`, `.sample`, `.template` and `.ejemplo` templates do), `passwords.yaml`, `*.pem`, `*.p8`, and ssh private keys.

## How a deploy works

```
local                                   server (<dir>)
-----                                   --------------
git archive <commit> → temp folder
flutter build web (each app)
pre_deploy hooks
select files, write .podship/  ──rsync──▶ .podship/upload/
                                        cp -al → releases/<id>/   (hard links: unchanged files cost nothing)
                                        link .env and passwords.yaml to the secrets files
                                        remote_pre_build; compose build (images <project>-<service>:<id>)
                                        back up the database
                                        compose up -d; current → releases/<id>
                                        health check (server URL, then public URL)
                                        on failure: compose up the previous release; current → previous
                                        mark the release ok; prune old releases and their images
post_deploy hooks
```

**Images are built on the server.** Developer machines are often arm64 and servers x86_64, and an rsync of changed source files is far smaller than a saved image. The server also keeps the Docker layer cache between deploys. `promote` moves the images that were already built and tested.

**The switch recreates containers.** It is not blue-green: the app is down for the seconds Docker needs to start the new containers. The reverse proxy points at fixed loopback ports, so it needs no change.

**Migrations.** With `migrations: on_start`, the server applies them when it starts (Serverpod's `--apply-migrations`, or `SERVERPOD_APPLY_MIGRATIONS=true`). With `maintenance`, podship runs the server once with `SERVERPOD_SERVER_ROLE=maintenance` before the switch, so a failed migration stops the deploy before traffic moves. A code rollback does not undo migrations. To go back in data too, use `rollback --with-db <stamp>`.

Every release folder has `.podship/compose.sh`, which runs `docker compose` with the right project, files and ports. On the server, `<dir>/current/.podship/compose.sh ps` works by hand.

## Backups

`backup now` runs `<podship_home>/lib/backup.sh` with the settings file `<podship_home>/etc/<unit>.conf` (paths only, no secrets). Each backup writes:

```
<backup dir>/daily/<YYYY-MM-DDTHHMM>/
  db.dump              pg_dump -Fc
  <volume>.tar.zst     each configured Docker volume
  counts.txt           rows per table at backup time
  SHA256SUMS
<backup dir>/encrypted/<YYYY-MM-DDTHHMM>.tar.age
                       the same files, plus .env and passwords.yaml
```

The encrypted copy is for `age` recipients: SSH public keys (`ssh-ed25519`, `ssh-rsa`) or age keys. List them in `backup.recipients`, as keys or as files like `~/.ssh/id_ed25519.pub`. Anyone with a matching private key can decrypt:

```
age -d -i ~/.ssh/id_ed25519 2026-10-06T0330.tar.age | tar -x
```

Retention keeps everything from today and yesterday, plus the newest backup of each of the last 14 days, 8 weeks and 6 months (configurable). It prunes only after a new backup is complete.

| Command | What it does |
|---|---|
| `backup now` | Takes a backup now, through the scheduled unit when it exists. |
| `backup list` | Stamps, sizes, and whether the encrypted copy exists. |
| `backup drill [stamp]` | Restores into a throwaway Postgres container with no network and no ports, compares row counts with the counts at backup time and with the live database, and deletes the container. Tables in `drill.volatile` may differ. |
| `backup restore [stamp \| --dump file]` | Asks you to type the project name, takes a fresh backup, stops the app services, renames the database to `<db>_before_<time>`, restores into a new one, starts the services and waits for health. To undo, swap the names back. |
| `backup schedule` | Installs the daily timer: systemd on Linux, launchd on macOS. `--show`, `--remove`. `backup.replaces` turns off older timers, so one environment never has two schedules. |
| `backup pull` | Copies new encrypted backups to `offsite.dir` on your machine (it never deletes there), and checks that the newest one decrypts with one of `offsite.identities` and that its checksums match. `--install-agent` runs it three times a day with launchd. |

The scripts run with bash 3.2 and BSD tools as well as GNU tools, so a Mac with Docker Desktop or colima can be a server too.

## Several projects on one server

Each server has one registry, at `<podship_home>/registry.yaml`. `link`, `deploy` and `adopt` write to it, and `destroy` removes the entry. podship checks it before any change: two environments cannot share a directory, compose project, port, domain, shared database or backup unit. `ports: {web: auto}` takes free ports from 20000–20999 and skips ports that something else listens on. An empty `backup.schedule` takes a free 15-minute slot from 03:00. `podship server status` and `podship projects list` show everything on the server.

Each environment runs its own Postgres by default. With `database: {mode: shared}`, `db provision` starts one `podship-postgres` container per server and gives the environment its own database and role.

## Domains and TLS

`domain add` routes the domains of an environment as written in `podship.yaml`:

- **Cloudflare Tunnel** (`proxy.kind: cloudflare_tunnel`): podship backs up the tunnel config, replaces the host's ingress rules (path rules first, before the catch-all), validates the result with `cloudflared tunnel ingress validate`, and restarts the tunnel (`systemctl restart` on Linux, `launchctl kickstart -k` on macOS). The DNS record is a proxied CNAME to `<tunnel-id>.cfargotunnel.com`.
- **Caddy** (`proxy.kind: caddy`): podship writes `/etc/caddy/podship/<compose project>.caddy`, imports it from the main Caddyfile, validates and reloads. Caddy gets the certificate from Let's Encrypt. The DNS record is an A or AAAA record to the server.

## Access and CI

`podship access add alice --key alice.pub --env production` adds Alice's key to the server's `authorized_keys`, marked `podship:alice`. `access remove alice` takes it out.

`podship ci setup --env staging` creates a deploy key, authorizes it, and prints the CI secrets and a GitHub Actions workflow that runs `podship deploy --env staging --yes`. CI needs no token, only the ssh key and the server's host key.

## Moving from hand-written scripts

See [docs/migrating-from-scripts.md](docs/migrating-from-scripts.md). It uses a real production setup as the example.

## Tests

The unit tests cover the config parser, file selection, release ids and retention, the server registry, plans, the `.env` and `passwords.yaml` editors, tunnel and Caddy routes, and the server scripts (syntax with bash 3.2, backup retention).

The integration test in `test/integration/flow_test.dart` deploys a small project to a real Docker host over ssh: a deploy, a failed deploy with automatic rollback, `rollback`, `rollback --to`, a backup, a drill, a restore, `env set`, `promote`, `status` and `destroy`. It runs only when `PODSHIP_IT_HOST` is set. `tool/it.sh` runs it and prints a short log.

## License

MIT. Copyright (c) 2026 Federico Ramallo.
