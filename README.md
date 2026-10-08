# podship

Deploy, back up and roll back [Serverpod](https://serverpod.dev) projects on your own servers, with production and staging.

podship is a command-line tool. It talks to your servers over ssh and runs everything with Docker Compose. Nothing runs on a server except Docker, the podship binary (`<podship_home>/bin/podship`), and one podship scheduler agent per machine (launchd on a Mac, a systemd timer on Linux) that runs the nightly backups and off-site pulls.

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
- **Backups.** `pg_dump -Fc` of the database, archives of Docker volumes (SQLite files copied with SQLite's backup API), row counts, checksums, and an encrypted copy that you decrypt with your SSH key. A nightly schedule, retention, a restore drill in a throwaway container, a restore that renames the old database instead of dropping it, and an off-site pull to your machine.
- **Scheduler.** One agent per machine, registered once. Its jobs (backups, off-site pulls) live in the machine's registry. See [Scheduler](#scheduler).
- **Domains.** Routes through a Cloudflare Tunnel, or Caddy with automatic Let's Encrypt certificates.
- **Cloudflare and SES.** DNS records, tunnel routes, Access apps and the app's email sender, through the Cloudflare and Amazon SES APIs, as plans you approve (see [Cloudflare and SES](#cloudflare-and-ses)).
- **Dry runs.** Every command that changes something takes `--dry-run` and prints its plan.

## Install

```
dart pub global activate --source git https://github.com/framallo/podship
```

This puts `podship` in `~/.pub-cache/bin`. Add that folder to your `PATH` if it is not there.

Then build the compiled executable:

```
podship self update
```

`dart pub global` runs podship from source, so every command first resolves dependencies and compiles (close to a second before anything happens). `self update` pulls the source it runs from (or clones the repository into `~/.podship/src/podship`), runs `dart compile exe`, writes `~/.podship/bin/podship`, and replaces the launcher script pub wrote in `~/.pub-cache/bin` with a two-line shim that runs the executable. Startup drops to a few milliseconds. Run it again to update. `podship self path` says what runs.

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
| `deploy` | Runs the tests, builds the images on this machine (see [Build location](#build-location)) and ships them, backs up the database (the three at the same time), uploads the release files, switches (in place or [blue/green](#zero-downtime)), checks health, rolls back on failure, prunes old releases and cleans the server. Flags: `--ref`, `--worktree`, `--skip-web`, `--skip-backup`, `--skip-hooks`, `--full-tests`, `--no-public-check`. See [Faster deploys](#faster-deploys). |
| `rollback` | Switches to the previous release, or to `--to <release>`. Code only. `--with-db <stamp>` also restores that backup first. |
| `promote <from> <to>` | Runs on `<to>` the exact release of `<from>`: the same files and the same images, with no build. Between servers with different CPU architectures it stops and tells you to deploy the same commit instead. |
| `restart [service…]` | Recreates the containers of the current release, for example after `env set`. |
| `adopt` | Records a setup that already runs (started by hand or by scripts) as a release, without restarting it, so `rollback` can come back to it. `--sha` names the commit when the folder is not a git checkout. |
| `status` | Current and previous releases, containers, health, disk and recent history. `--watch`. |
| `logs` | Container logs. `--service`, `--since`, `--until`, `--tail`, `--follow`, `--timestamps`. |
| `releases list`, `releases history` | The releases on the server; the deploys, rollbacks and promotions. |
| `env list/get/set/unset` | Plain variables in the environment's `.env`. |
| `secret init/list/set/unset/copy` | Secrets in `.env` and `passwords.yaml`. `set` reads the value from stdin, a hidden prompt, `--from-file` or `--generate`. `copy --from <env>` copies values between environments without showing them. `init` creates both files with fresh random values. |
| `backup now/list/drill/restore/schedule/pull` | See [Backups](#backups). |
| `scheduler install/status/list/run-once/uninstall` | The nightly scheduler agent of a machine. See [Scheduler](#scheduler). |
| `db connect` | `psql` on the environment database. |
| `db migrate status` | The applied Serverpod migrations, against the newest one in the current release. |
| `db user list/create/reset-password/delete` | Database roles for people and tools. The password is printed once. |
| `db provision` | Shared-Postgres mode: starts `podship-postgres` once per server and creates the environment's database and role. |
| `db wipe` | An empty database. The old one is renamed, not dropped. |
| `tunnel forward` | Forwards a local port to a service port that is not published, like Serverpod Insights (`--service server --port 8081`) or Postgres (`--service postgres --port 5432`). `podship tunnel --service …` still works and means `tunnel forward`; a bare `podship tunnel` shows the subcommands. |
| `tunnel list/route/unroute/create` | Cloudflare Tunnels of the account; route or unroute hostnames of the environment (through the API for a remotely-managed tunnel, or its `config.yml`); create a remotely-managed tunnel. |
| `dns plan/apply/list` | The DNS records of the domains in Cloudflare: the plan (create/update/delete, before and after), the apply after approval, and the records with drift. |
| `email status/setup/test` | The app's sender in Amazon SES: whether it can send, the identity, DKIM and MAIL FROM setup, a test email. |
| `app setup/teardown` | One plan and one approval for a whole app: registry and ports, tunnel route, DNS, Access, TLS check, SES sender; teardown undoes it. |
| `domain add/remove/list` | Routes domains through a Cloudflare Tunnel or Caddy, and prints the DNS record you need. With `--provider cloudflare` (or `dns.provider: cloudflare`), also creates the record and the Access app, after a plan and an approval (`--plan`, `--plan-id`). |
| `server bootstrap` | Installs Docker, compose, age, zstd, the firewall rules and podship's folders. Safe to run again. |
| `server status` | Every project on the server: registry, containers, CPU and memory, disk. |
| `images check` | Builds the current commit here, ships it, starts the server image on a test port with a throwaway Postgres, checks `/health`, removes it all. `--ship`, `--gate`, `--services`. |
| `images prune` | Removes old images, the Dart SDK images and the build cache on the server; reports the disk saved. |
| `projects list` | The server registry. |
| `access list/add/remove` | Per-person ssh keys on a server, marked `podship:<name>` in `authorized_keys`. |
| `ci setup` | Creates an ssh deploy key for CI, gives it access, and prints a GitHub Actions workflow. |
| `destroy` | Removes an environment: containers, volumes, images, files, routes, schedule and registry entry. `--purge-backups` also deletes its backups. |

Global options: `--project-dir <dir>` (`-C`), `--ssh-key <file>`, `--yes`, `--verbose`, `--quiet`, `--notify` / `--no-notify` (see [Notifications](#notifications)).

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
      inputs: []                    # more folders whose changes need a new build (see Faster deploys)
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

- `host: local` runs the environment on this machine: scripts run with the local `bash` instead of ssh, uploads are a local rsync, `backup pull` is a local copy, and `tunnel forward` prints the local port. Use it for a Mac that hosts its own projects.
- `remote_post_switch` (under `compose`, or per environment): shell commands that run on the server in the new release's folder after the switch and the health checks, before the release is marked healthy. A failure rolls the deploy back. Use it for a host service that runs next to the containers, like a launchd agent. `--skip-hooks` skips them.
- `compose_project` (default: the project name for `production`, `<project>-<env>` for the others), `compose_files` (extra compose files for this environment only), `run_mode`, `plain_env` (variables whose values may be printed), `remote_path` (added to the front of `PATH` on the server), `podship_home` (default `/srv/podship`), `server_service` (default `server`), per-environment `build_contexts` and `remote_pre_build`. (`scheduler: auto|systemd|launchd` is still accepted and ignored: the agent detects the OS of the machine.)
- `health.fallback_urls` and `health.public_fallback_urls`: other URLs that also count as healthy, so a rollback to a release from before a health route moved still passes. `health.attempts`, and `health.interval` in seconds.
- `secrets.env_file` and `secrets.passwords_file` (relative to `dir`; default `shared/.env` and `shared/passwords.yaml`), `secrets.passwords_link` (where each release sees `passwords.yaml`), and `secrets.password_keys`.
- `backup.dir`, `unit`, `schedule` (kept for the registry's backup slot; the nightly run time is the machine's, see [Scheduler](#scheduler)), `timezone`, `retention` (`days`, `weeks`, `months`), `compression` (`zstd` or `gzip`), `layout` (the `plain`, `encrypted`, `dump`, `counts` and `secrets` names), `stop_on_restore`, `drill.tables` and `drill.volatile` (globs), `offsite.identities`, `before_deploy`, and `replaces` (older schedule units to turn off).
- `proxy.kind` (`cloudflare_tunnel`, `caddy` or `none`), `proxy.config`, `proxy.service`, `proxy.tunnel_id` and `proxy.managed` (`remote`: the tunnel's ingress lives in Cloudflare and podship edits it through the API; `local`: a `config.yml` on the host. Default: `local` when `proxy.config` is set, else `remote`).
- `dns` (`provider: cloudflare` or `none`, `zone`, `account_id`, and for Caddy `ipv4`, `ipv6`, `proxied`), `email` (`from`, `region`, `provider: ses`, `identity`, `mail_from`, `env`), `domains[].access` (`emails`, `email_domains`, `session`), and at the top level `cloudflare: {account_id}`. See [Cloudflare and SES](#cloudflare-and-ses).

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
podship machine (laptop, build Mac)              server (<dir>)
-----------------------------------              --------------
git archive <commit> → temp folder
 ┌ tests (suites, by hash)
 ├ images: web (cache) · dart build cli
 │   (cross-compiled) · other services ·
 │   runtime image · release gate · ship  ──────▶ docker load (only missing layers)
 └ backup ───────────────────────────────────────▶ back up the database
select files, write .podship/  ──rsync──▶ .podship/upload/ → releases/<id>/ (hard links)
                                          compose up (in place) or start blue/green + flip
                                          health check (server URL, then public URL)
                                          on failure: back to the previous release
                                          mark ok; prune releases; server hygiene
post_deploy hooks
```

The three lanes (tests, images, backup) run at the same time; the switch waits for all three. `history --verbose` shows each lane's steps (`images: Compile the server…`).

**Migrations.** With `migrations: on_start`, the server applies them when it starts (Serverpod's `--apply-migrations`, or `SERVERPOD_APPLY_MIGRATIONS=true`). With `maintenance`, podship runs the server once with `SERVERPOD_SERVER_ROLE=maintenance` before the switch, so a failed migration stops the deploy before traffic moves. A code rollback does not undo migrations. To go back in data too, use `rollback --with-db <stamp>`.

Every release folder has `.podship/compose.sh`, which runs `docker compose` with the right project, files and ports. On the server, `<dir>/current/.podship/compose.sh ps` works by hand.

### Faster deploys

A deploy does only the work that the commit needs:

- **Flutter web builds are reused.** Each app has an input hash: the git tree ids of its folder, of its `path:` dependencies (read from its `pubspec.yaml`), of the nearest `pubspec.lock`, plus `flutter_web[].inputs`, the Flutter version, `base_href` and `args`. The hash goes into the release's `release.json`. When a kept, healthy release on the server has the same hash, the new release hard-links that build (`Reuse Flutter web: app`) and `flutter build web` does not run. The hash comes from the commit, so a `--worktree` deploy always builds. `reuse: false` on an app turns this off.
- **Unchanged test suites are skipped.** Each suite has the same kind of hash (its `dir`, path dependencies, lock, `tests.suites[].inputs`, the command). A passing run writes `<podship_home>/history/<project>/tests/by-hash/<suite>-<hash>.json`; the next deploy whose suite has that hash skips it and reports `tests server: unchanged since <sha>, skipped`. The commit's own test record still says `ok`, with `same_as: <sha>` on the skipped suite, so the production gate works as before. `deploy --full-tests` runs everything; `skip_unchanged: false` on a suite does too.
- **Suites run at the same time** (`tests.parallel`, default `true`): each one in its own folder. Set `parallel: false` for suites that share a resource.
- **The upload sends changed content only.** rsync runs with `--checksum`: `git archive` gives every file the commit's time, so a new commit would otherwise re-send everything.
- **Images build from cache.** With `build: remote`, the server keeps the BuildKit cache between releases (with a local build, this machine does). Order the Dockerfile so dependencies come first (`COPY pubspec.lock` and `pubspec.yaml`, `RUN --mount=type=cache,target=/root/.pub-cache dart pub get`, then the sources, then the compile), and copy `web/`, `config/` and `migrations/` straight from the build context into the final image, so a web-only change does not recompile the server. Pin base images.
- **Stage timings.** Every history record has `data.steps` (title and duration of each step). `podship history --verbose` prints them; `last_deploy` through a console or MCP returns the newest one.

## Build location

The server only runs the app. Images are built on the machine that runs podship, which has more CPU and disk and keeps the caches. `build:` per environment:

```yaml
environments:
  staging:
    build: local                 # or a map:
    # build:
    #   location: auto           # auto (default) | local | local-docker | remote
    #   mode: aot                # aot | jit (jit is refused for production)
    #   ship: auto               # auto (= load) | load | registry | ghcr
    #   platform: linux/amd64    # default: ask the server's Docker
    #   contexts:                # services whose build_contexts are server paths
    #     pacewright: {git: git@github.com:you/pacewright.git, ref: main}
    #   prune: true              # server hygiene after a healthy deploy
```

- **local**: `dart build cli --target-os linux --target-arch <server arch>` compiles the Serverpod server on this machine. Dart 3.8 and later cross-compile for Linux, native assets included (sqlite3, argon2), so an arm64 Mac compiles for an x86_64 VPS without emulation. podship then keeps the final stage of the project's own Dockerfile and replaces each `COPY --from=<build stage>` with the files from this machine: `/runtime/` comes from the build stage's image (`COPY --from=dart:3.12.2 /runtime/ /`), `…/build/bundle/` is the compiled bundle, other paths map back to the context. FROM, ENV, RUN, ENTRYPOINT stay as written. No Dart SDK reaches the server.
- **local-docker**: `docker buildx build --platform <server platform>` of the project's Dockerfiles on this machine. Used when Dart cannot compile for the server, or when asked. RUN steps of another CPU run emulated.
- **remote**: the old way, the server builds from the uploaded files. Used when asked, or as the fallback with the reason in the log: no Docker or no `docker buildx` on this machine, or a server that does not run Linux containers.

Other built services (a browser image, a daemon) are built here with buildx at their compose `platform:` (or the server's). A service whose `build_contexts` entry is a server path builds on the server unless `build.contexts` gives it a local path or a git URL (cloned to `~/.podship/cache/src`).

What makes a repeat deploy cheap: the web builds come from `~/.podship/cache/web` by input hash; a server image with the same inputs (sources, lock, Dockerfile, web hashes, platform, Dart version) is tagged again without a compile; buildx's cache makes other images a cache hit; an image whose ID the server has is only tagged there.

`podship images check --env vps` builds the current commit here, ships it, starts the server image on the server in a throwaway stack (its own network and Postgres, throwaway Serverpod passwords, a test port on loopback), checks `/health`, and removes it all. No release, no switch, no DNS. `--ship registry` compares shipping methods; `--gate` runs the release gate first.

## Images

How images reach the server (`build.ship`):

- **load** (default): `docker save`, then only the layers the server lacks, `zstd`, ssh, `docker load`. podship reads each layer's DiffID from the image config, asks the server for the DiffIDs of its images, and leaves those blobs out. This needs the containerd image store on the server (Docker 29 default, Docker Desktop, Colima); otherwise every layer travels. If a trimmed load fails, podship sends the whole archive.
- **registry**: a `registry:2` container on this machine (`podship-registry`, 127.0.0.1 only, htpasswd bcrypt login in `~/.podship/registry/`, mode 0600). The server pulls by digest through an ssh reverse tunnel; the password goes on stdin, the server logs out after. Docker Desktop servers cannot reach the tunnel (their daemon's 127.0.0.1 is a VM): podship uses load there and says so.
- **ghcr**: push to `build.ghcr` with this machine's Docker login; the server logs in with `gh auth token` on stdin, pulls, logs out.
- With `host: local` nothing ships: the images are already in the server's Docker.

Measured on the VPS link (x86_64, 43 MB of new layers): load 10–11 s, registry 37 s. Load is the default.

**Server hygiene.** After a healthy deploy that built nothing on the server, podship removes images of this environment that no kept release uses, dangling images, the Dart SDK images and the build cache, and logs the disk saved (`docker system df` before and after). `podship images prune --env X` does it on demand (`--dry-run` prints the script). Never on `host: local`, where the builds happen.

**Release gate in containers.** `tests.gate` takes a map with an `image:` entry. The new image runs on this machine with its services (default: Postgres with throwaway passwords), and a test-runner container runs the project's command against it, before the image ships. The runner image is built by podship once and cached: Debian, Flutter (this machine's version, or `flutter:`), and a browser with its driver: Chrome for Testing and its chromedriver (pinned, `chrome:`) on amd64, Debian's Chromium and chromium-driver on arm64 (Chrome for Testing has no Linux arm64 build). chromedriver listens on 4444; `PODSHIP_GATE_SERVER` is the server's URL; `artifacts` are copied to `~/.podship/artifacts/<project>/<env>/<release>/`. No host chromedriver, no SDK on the server.

```yaml
tests:
  gate:
    environments: [production]     # environments that only take tested commits (the old list)
    image:
      environments: [staging]      # deploys that run the gate (empty: all)
      dir: app
      command: flutter drive --driver=test_driver/integration_test.dart --target=integration_test/gate_test.dart -d web-server --browser-name=chrome --driver-port=4444 --headless --dart-define=API=$PODSHIP_GATE_SERVER/
      seed: dart run tool/seed.dart  # optional; seed_in: runner (default) or server
      services:                      # optional; default: Postgres
        postgres: {image: "postgres:16-alpine", env: {POSTGRES_PASSWORD: gate}, ready: pg_isready -U postgres}
      server:                        # optional
        entrypoint: [./bin/server, --mode=staging, --apply-migrations]
        env: {SERVERPOD_PASSWORD_database: gate}
        port: 8082
        health: /health
      artifacts: [build/e2e]
      timeout: 1800
```

## Zero-downtime

`switch: blue_green` on an environment. The new release starts next to the running one in its own compose project (`<project>-blue` or `-green`) with no host ports; it joins the network `<project>-front` with aliases like `green-server`. podship waits until `/health` and `/readyz` answer inside the new server container, then rewrites the config of the front (`<project>-front`, nginx `stream`, owns the environment's loopback ports) and reloads it: open connections finish, new ones go to the new color. The old color stops (kept, so a rollback starts it fast). `rollback` flips the same way; a failed health check flips back.

Both colors share the data: the database must run outside the release (`database.mode: shared`), and named volumes keep the base project's names (`<project>_<volume>`), so backups see the same volumes. Without a shared database podship switches in place and says why. The first blue/green deploy stops the base project right before the front takes its ports (a second or two); later flips drop nothing. Measured on a test project at 50 requests per second: 0 failed requests across a flip; in place, a 3.6 s gap.

**In place** (the default) recreates the containers: the app is down for the seconds Docker needs to start them. The proxy points at fixed loopback ports, so it needs no change.

## Backups

The backup, the drill and the restore run on the server as `podship agent backup|drill|restore --conf <podship_home>/etc/<unit>.conf`, from the podship binary at `<podship_home>/bin/podship`. Every backup command first puts this podship there when its checksum differs (a Linux server gets a cross-compiled binary). The settings file holds paths only, no secrets. Each backup writes:

```
<backup dir>/daily/<YYYY-MM-DDTHHMM>/
  db.dump              pg_dump -Fc
  <volume>.tar.zst     each configured Docker volume
  counts.txt           rows per table at backup time
  SHA256SUMS
<backup dir>/encrypted/<YYYY-MM-DDTHHMM>.tar.age
                       the same files, plus .env and passwords.yaml
```

The encrypted copy is for `age` recipients: SSH public keys (`ssh-ed25519`, `ssh-rsa`) or age keys. List them in `backup.recipients`, as keys or as files like `~/.ssh/id_ed25519.pub`. A `backup.volumes` entry's `volume` is a Docker volume name or an absolute host folder (a bind mount, like `/Users/me/services/app-data/data`).

Anyone with a matching private key can decrypt:

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
| `backup schedule` | Writes the backup job (`backup:<project>/<env>`) into the server's registry and installs the podship binary and the settings it runs with. The server's scheduler agent runs it every night. No launchd or systemd unit per environment. `--show` prints the job and its last run, `--remove` removes it. |
| `backup pull` | Copies new encrypted backups to `offsite.dir` on your machine (it never deletes there), and checks that the newest one decrypts with one of `offsite.identities` and that its checksums match. `--schedule` writes the pull job (`pull:<project>/<env>`) into this machine's registry instead, for its scheduler agent; `--schedule --remove` removes it. |

The server needs Docker, `age` and `zstd` on its PATH; the agent itself is the podship binary, so a Mac with Docker Desktop or colima can be a server too.

## Scheduler

podship registers **one background agent per machine, once**: `dev.podship.scheduler` with launchd on a Mac, `podship-scheduler.timer` with systemd on Linux. The agent runs `podship scheduler tick --home <podship home>` once a night (03:00 machine local time by default) and once at load (login, reboot). Nothing else is registered per environment, and a deploy never touches launchd or systemd.

The jobs live in the machine's registry (`<podship_home>/registry.yaml`):

```yaml
scheduler:
  at: "03:00"                                    # the nightly run, machine local time
jobs:
  "backup:shop/production":
    kind: backup
    project: shop
    env: production
    conf: /srv/podship/etc/podship-backup-shop.conf
    log: /srv/podship/log/podship-backup-shop.log
    path: /usr/local/bin:/usr/bin:/bin
  "pull:shop/production":                        # on the machine that keeps the off-site copies
    kind: pull
    project: shop
    env: production
    project_dir: /Users/me/work/shop
```

`backup schedule` writes a backup job into the server's registry; `backup pull --schedule` writes a pull job into this machine's registry. Each run executes every job that has not run on today's local date, backups first, then pulls. A machine that was asleep or off catches up with one run when it comes back (launchd fires a missed calendar time on wake; the systemd timer is persistent); several missed nights still give one run, never a burst. Daylight-saving changes neither skip nor double a night. Each job runs under its own lock, so a job still running is skipped, and a failing job never stops the others or the agent.

The agent keeps `<podship_home>/scheduler/state.json` (last tick, and per job the last run, its outcome and backup stamp), appends to `<podship_home>/log/scheduler.log`, and writes a history record per run under `<podship_home>/history/<project>/<env>/` (actor `podship-scheduler`), like a manual `backup now`.

```
podship scheduler install --env production          # the server of production
podship scheduler install --at 04:00                # this machine (the off-site pulls)
podship scheduler status --env production
podship scheduler list
podship scheduler run-once backup:shop/production --env production
podship scheduler run-once pull:shop/production
podship scheduler uninstall --env production        # the registry and its jobs stay
```

`install` puts a compiled podship at `<podship_home>/bin/podship` (this executable when it is a compiled podship, else a fresh `dart compile exe` of the package; `--binary` names one; the machine must have the same OS and CPU architecture), imports the per-environment agents an older podship installed (`dev.podship.backup.*` and `dev.podship.pull.*` launch agents, `podship-backup-*` systemd timers) into the registry, boots them out and renames their files `.migrated-by-podship`, turns off the units in `backup.replaces`, and registers the agent. It is idempotent: a second install with nothing changed changes nothing, and macOS shows its "can run in the background" notice only when the plist really changed. Imported jobs start the next night (the install marks them as run today), so `run-once` is the way to test one now. After a podship upgrade, run `scheduler install` again on each machine to update the binary.

Pick the run times so a machine that pulls fires after the machine that backs up: for example 03:00 on the server and 04:00 on your Mac.

The protocol exposes `scheduler.list` (list_schedules), `scheduler.run` (run_job), `scheduler.status` and `scheduler.install` for consoles and MCP tools.

## Several projects on one server

Each server has one registry, at `<podship_home>/registry.yaml`. `link`, `deploy` and `adopt` write to it, and `destroy` removes the entry. podship checks it before any change: two environments cannot share a directory, compose project, port, domain, shared database or backup unit. `ports: {web: auto}` takes free ports from 20000–20999 and skips ports that something else listens on. The registry also holds the machine's nightly run time and its scheduled jobs (see [Scheduler](#scheduler)). `podship server status` and `podship projects list` show everything on the server.

Each environment runs its own Postgres by default. With `database: {mode: shared}`, `db provision` starts one `podship-postgres` container per server and gives the environment its own database and role.

## Domains and TLS

`domain add` routes the domains of an environment as written in `podship.yaml`:

- **Cloudflare Tunnel** (`proxy.kind: cloudflare_tunnel`): podship backs up the tunnel config, replaces the host's ingress rules (path rules first, before the catch-all), validates the result with `cloudflared tunnel ingress validate`, and restarts the tunnel (`systemctl restart` on Linux, `launchctl kickstart -k` on macOS). The DNS record is a proxied CNAME to `<tunnel-id>.cfargotunnel.com`.
- **Remotely-managed Cloudflare Tunnel** (`proxy.kind: cloudflare_tunnel` without `proxy.config`, or `proxy.managed: remote`): podship reads the tunnel's configuration through the API, replaces the rules of the hostname (other rules and the catch-all stay), and writes it back. Nothing changes on the host. podship refuses to write the API configuration of a tunnel whose `source` is `local`: that tunnel reads a `config.yml` on its host (like a laptop's tunnel), so set `proxy.config` for it.
- **Caddy** (`proxy.kind: caddy`): podship writes `/etc/caddy/podship/<compose project>.caddy`, imports it from the main Caddyfile, validates and reloads. Caddy gets the certificate from Let's Encrypt. The DNS record is an A or AAAA record to the server.

With a locally-managed tunnel and `proxy.origin_certs`, podship creates the record with `cloudflared tunnel route dns`. Beware: given a hostname outside the cert's zone, cloudflared appends the cert's zone (it created `www.cazafacturas.mx.densitylabs.io` once). podship picks the cert of the longest matching zone only, and checks the name cloudflared reports; but `dns.provider: cloudflare` is the safer path, because the API resolves every hostname to its zone by longest suffix among the zones the token can read, and refuses when none matches.

## Access and CI

`podship access add alice --key alice.pub --env production` adds Alice's key to the server's `authorized_keys`, marked `podship:alice`. `access remove alice` takes it out.

`podship ci setup --env staging` creates a deploy key, authorizes it, and prints the CI secrets and a GitHub Actions workflow that runs `podship deploy --env staging --yes`. CI needs no token, only the ssh key and the server's host key.

## More commands

| Command | What it does |
|---|---|
| `releases overview` | What runs where: every environment, its current release and commit. |
| `releases containing <sha>` | Which environments run a release that contains a commit (by git ancestry). |
| `history [--all]` | Every operation on the server: who, when, the release, the duration, the outcome, and a log. |
| `unlock` | Removes the environment lock left by a client that stopped in the middle of an operation. |
| `scale --replicas N` | Changes the number of server containers of the current release (see [Serverpod operations](#serverpod-operations)). |
| `loadtest [--path] [--users] [--duration]` | Load tests an environment with k6, from its own server, and prints latency and errors. |
| `provider login <name>`, `provider offers <name> [--country MX]` | Provider credentials (kept in the system's secret store: `vultr`, `hostinger`, `cloudflare`, `aws`) and the regions, plans and prices of server providers. |
| `provider check cloudflare`, `provider check aws --region <r>` | Read-only checks of the stored credentials: the token's status and the zones it reads; the SES account of a region. |
| `server create`, `server destroy` | Buys or deletes a server at a provider; `create` also bootstraps it. Both ask you to type the server name. |
| `console install` | Sets up a podship console on a machine, deployed by podship itself. |
| `login`, `logout`, `whoami` | Personal access tokens for a podship console. |
| `operations [--json]` | The operation catalog: stable names and parameters as JSON schema. |

## Tests before a deploy

`tests:` in `podship.yaml` lists test suites. They run after the commit is exported and before anything is built or uploaded. A failed suite stops the deploy, and the result names the failed tests.

```yaml
tests:
  runner: local            # local: on the machine that runs podship; container: on the server, before the build
  gate: [production]       # environments that only take tested commits
  suites:
    - name: server
      dir: shop_server
      command: <the test command, like your test runner with --concurrency=1>
      timeout: 1800
      environments: [staging]
    - name: app
      dir: shop_flutter
      command: <the Flutter test command>
      environments: [staging]
```

Each suite's counts, failures, duration and log go into the operation result, the history, and a per-commit record on the server (`<podship_home>/history/<project>/tests/<sha>.json`). An environment in `gate` takes a commit only if its tests passed in this deploy or in another environment's deploy of the same commit (staging, usually). Otherwise `deploy --skip-tests --reason "…"` asks you to type the environment name, and the skip is recorded. A project without suites has no gate. With `runner: container`, each suite runs in `image:` (default `dart:stable`) on the server, from the uploaded files.

## Notifications

podship tells you when a deploy starts, when it is done (release, duration, health), when it fails (with the result of the automatic rollback), when a rollback is done, when a backup fails, and when a scheduler job fails. Channels:

| Channel | What it does |
|---|---|
| `macos` | A notification on the machine that runs the CLI (`terminal-notifier` when installed, else `osascript display notification`). |
| `email` | An email through SES, with the environment's `email.from` and `email.region` unless the channel sets its own. Uses the AWS credentials of `podship provider login aws`. |
| `webhook` | A JSON `POST` with headers `X-Podship-Event`, `X-Podship-Timestamp` and, with a secret, `X-Podship-Signature: sha256=<hex>`: HMAC-SHA256 of `<timestamp>.<raw body>`. |
| `slack` | A Slack-compatible incoming webhook (`{"text": …}`). |

```yaml
notify:
  events: [deploy_done, deploy_failed, rollback_done, backup_failed, scheduler_job_failed]   # the default; add deploy_started
  bell: true                              # a terminal bell after a long command
  channels:
    macos: {}
    ops-mail: {kind: email, to: [ops@shop.example]}
    slack: {url_env: SHOP_SLACK_WEBHOOK, events: [deploy_failed, backup_failed]}
    hook:  {kind: webhook, url: https://ci.shop.example/podship, secret_env: PODSHIP_WEBHOOK_SECRET}
```

Without a `channels:` block, the `macos` channel is on by itself, so the machine that runs the CLI gets a desktop notification when a deploy ends. A channel's key is its name; `kind` defaults to the name when it is one of the four. Each channel takes the events of `notify.events` unless it lists its own `events`. `podship.yaml` is committed, so URLs with tokens and the webhook secret do not belong there: put them in `~/.podship/config.yaml` (the same `notify:` block; the project's settings win channel by channel), or name an environment variable with `url_env` / `secret_env` (default `PODSHIP_WEBHOOK_SECRET`). A channel that fails or does not answer in 15 s is a warning; it never fails or slows a deploy. Notifications carry no secret values.

After every command that takes more than 20 s, the CLI rings the terminal bell (unless `bell: false` or `--no-notify`) and prints one line: `deploy staging ok: 20261008-020102-0314c97 in 48.2 s (build 12.1 s, backup 7.3 s, switch 9.2 s)`. `--no-notify` sends nothing; `--notify` sends even when the config says `enabled: false`.

For consoles and MCP: the protocol operation `subscribe_events` (optional `events` and `env` filters) streams every notification of the server as a `notification` event and does not end; `last_deploy` returns the newest deploy record of an environment, with its stage timings. The scheduler reports a failed job with `Notification.schedulerJobFailed(...)` through the same `Notifier`.

## GitHub

```yaml
github:
  repo: owner/name
  tags: true               # podship/<env>/<release> on the deployed commit
  deployments: true        # GitHub Deployments with status (in_progress, success, failure, inactive after a rollback)
  statuses: true           # commit status podship/deploy/<env>
  releases: [production]   # a GitHub Release per deploy, with notes
  release_tag: v{date}-{n}
```

podship uses the `gh` CLI with your own login. The release notes list the commits since the previous release of that environment, the merged pull requests, `Implements:` commit trailers as features, and the test summary. A rollback marks the deployment that was running inactive and adds a note to its release. A GitHub failure is a warning; it never fails a deploy.

## Serverpod operations

`serverpod:` in an environment follows Serverpod's operations guide:

```yaml
serverpod:
  readiness: true          # also gate deploys on Serverpod's /readyz (web port, else api port)
  logs:                    # session and query logs, so the log tables never grow without bound
    retention_period: 30d
    retention_count: 100000
    cleanup_interval: 24h
    persistent: true
  db_pool: 10              # database connections per server container
  stop_grace: 30           # seconds to drain on stop (Serverpod drains on SIGTERM)
  replicas: 1              # above 1: serverless replicas, a sticky load balancer, Redis
  redis: false
  exception_dsn_env: SENTRY_DSN   # the .env variable the app's exception reporter reads
```

- **Logs.** The settings become `SERVERPOD_SESSION_LOG_*` variables of the server. `podship status` shows the rows and size of `serverpod_session_log`, `serverpod_log`, `serverpod_query_log` and `serverpod_message_log`.
- **Health.** The deploy gate checks the app's health URL and Serverpod's `/readyz`. A failure in either rolls back. `health.public_checks` adds checks of public URLs after the switch, from this machine: each has `url` (`{port:name}` works), optional `method`, `status` (a number or a list; default any 2xx), `content_type` (a substring of the header) and `contains` (a substring of the body). All must pass within `attempts` × `interval`, or the deploy rolls back. Use it for routes a catch-all could shadow: a JSON config, an API that must answer 401 as JSON, a 404 on another host. `--no-public-check` skips them.
- **TLS.** Serverpod does not terminate TLS itself; the Cloudflare Tunnel or Caddy in front does (see [Domains and TLS](#domains-and-tls)).
- **Scaling.** With `replicas: N`, the release has the `server` (monolith role: it runs future calls) and `N-1` `server-replica` containers with the serverless role, an nginx load balancer (`podship-lb`) on the server's published ports with `ip_hash`, so a client's stream stays on one container, and Redis for messages, caching and token revocation. Migrations run once: with `migrations: maintenance`, a maintenance-role container applies them before the rollout. Services inside the project that call the server directly (an nginx sidecar, for example) should call `podship-lb` instead. `podship scale --replicas N` changes the count later. If the compose file pins `--role` in the server's entrypoint, set `replica_entrypoint`.
- **Graceful shutdown.** `stop_grace` becomes the server's `stop_grace_period`.
- **Load testing.** `podship loadtest` runs k6 on the server against the environment's own port.
- **Exception monitoring.** Serverpod reports exceptions through the app's own handler; podship keeps the DSN as a secret and passes it to the server through `.env`.

## Egress proxy

Some sites block data-center addresses. `egress:` sends chosen containers' outgoing traffic through a proxy:

```yaml
egress:
  proxy: socks5://user:pass@mx-exit.example.com:1080
  applies_to: [chrome, server]
  no_proxy: [localhost, 127.0.0.1, postgres]
```

Each listed service gets `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY` and `NO_PROXY`. A service named `chrome` also gets `PODSHIP_CHROME_PROXY`, for an entrypoint that passes it to Chrome's `--proxy-server`.

## Server providers

`podship server create --provider vultr --name shop-mx --region mex --plan vc2-2c-4gb` buys a server, waits until it answers, and bootstraps it. Store the API token first with `podship provider login vultr`. `--dry-run` prints the API requests without sending them. `podship server destroy` deletes one.

| Provider | Mexico | Notes |
|---|---|---|
| Vultr | `mex` (Mexico City) | Billed by the hour; delete stops billing. |
| Hostinger | none (Phoenix, São Paulo are closest) | A purchase on the default payment method; the API cannot delete a VPS, so `destroy` turns off auto-renewal. |

Other providers with a Mexico location: AWS EC2 `mx-central-1`, Google Cloud `northamerica-south1`, Azure Mexico Central, Oracle Cloud Querétaro and Monterrey. Providers are plugins: implement `ServerProvider` and call `registerProvider`.

## Tunnel routes

`TunnelRoutes` adds or removes "hostname → loopback port" rules on a server's cloudflared. `domain add` uses it, and other tools can too:

```dart
final routes = TunnelRoutes(Ssh(), Log((e) => print(renderEventText(e))));
final result = await routes.apply(
  TunnelTarget(
    host: 'user@server',
    config: '/home/user/.cloudflared/config.yml',
    service: 'com.cloudflare.my-tunnel',   // systemd unit or launchd label
    tunnelId: '<tunnel id>',
    podshipHome: '/home/user/podship',
    originCerts: {'example.com': '/home/user/.cloudflared/cert.pem'},
  ),
  [RouteChange('preview.example.com', [ResolvedRoute(null, 20010)])],
);
print(result.dns);   // created, exists, or the CNAME to add by hand
```

Every editor takes the lock `<podship_home>/locks/cloudflared` on that server and waits for it, so two tools never edit the config at once. The config is backed up, validated with `cloudflared tunnel ingress validate`, and the tunnel restarts only when a rule changed. A `RouteChange` with no routes removes the hostname.

## The library

Everything the CLI does is in `package:podship/podship.dart`. The CLI is a thin layer over it.

```dart
import 'package:podship/podship.dart';

final podship = Podship(PodshipConfig.load('/path/to/project'));

// Operations that change something: a live event stream and a result.
final op = podship.deploy('staging');
await for (final e in op.events) {
  print(renderEventText(e) ?? '');          // or e.toJson()
}
final result = await op.result;             // OperationResult: ok, release, duration, error, data
print(result.toJson());

// Reads return typed values with toJson().
final status = await podship.status('production');           // EnvStatus
final releases = await podship.releases('production');       // List<ReleaseInfo>
final overview = await podship.overview();                   // what runs where
final where = await podship.releasesContaining('a0dc2b0');
final history = await podship.history('production');         // List<HistoryRecord>
final backups = await podship.backups('production');         // List<BackupInfo>
```

- **Cloudflare and SES**: plans (reads that return a `ChangeSet`) `dnsPlan`, `domainPlan`, `tunnelPlan`, `emailPlan`, `appPlan`, `teardownPlan`; operations `dnsApply`, `domainAdd`/`domainRemove` with `provider` and `planId`, `tunnelRoute`, `tunnelUnroute`, `tunnelCreate`, `emailSetup`, `emailTest`, `appSetup`, `appTeardown`; reads `dnsRecords`, `dnsDrift`, `tunnels`, `emailStatus`. `Podship(config, integrations: Integrations(secrets: …, transport: …))` takes a console's secret store and, in tests, a `FixtureTransport`.
- **Operations**: `deploy`, `rollback`, `promote`, `restart`, `adopt`, `link`, `destroy`, `unlock`, `scale`, `loadtest`, `backupNow`, `backupDrill`, `backupRestore`, `backupSchedule`, `backupPull`, `envSet`, `envUnset`, `secretSet`, `secretUnset`, `secretCopy`, `secretCopyAll`, `secretInit`, `domainAdd`, `domainRemove`, `bootstrap`, `dbProvision`, `dbWipe`, `dbUser`, `access`, `serverCreate`, `serverDestroy`. An `Operation` starts when you first read `events` or `result`, and `op.request` is its protocol request: you can send it to a console instead of running it.
- **Events**: `OperationStarted`, `PlanReady`, `StepStarted`, `StepFinished`, `StepFailed`, `LogLine`, `SuiteStarted`, `TestFailed`, `SuiteFinished`, `OperationFinished`. Each has `toJson()`; `eventFromJson` reads them back. Events never carry secret values.
- **Reads**: `status`, `releases`, `currentRelease`, `overview`, `releasesContaining`, `backups`, `envList`, `envGet`, `secretList`, `projects`, `serverStatus`, `domains`, `migrateStatus`, `history`, `lastDeploy`, `logs` (a stream of lines), `lockHolder`.
- **Notifications**: `Podship(config, notifier: Notifier(config.notify, …))`; `Notifier.stream` is every notification of the process, `OperationWatcher` turns an operation's events into them (see [Notifications](#notifications)).
- **`--json`**: read commands print JSON documents; commands that change something print one JSON event per line, ending with a `result` event.

### History

Every operation that changes an environment writes a record on that environment's server:

```
<podship_home>/history/<project>/<env>/<UTC time>-<operation>.json   who, when, release, previous release,
                                                                     duration, outcome, error, data, log path
<podship_home>/history/<project>/<env>/<UTC time>-<operation>.log    the operation's events as text
<podship_home>/history/<project>/tests/<sha>.json                    test results of a commit
```

`podship history` and `Podship.history` read them; `--all` reads every project on the server. Records hold no secret values (a one-time password from `db user create` stays out of them).

### The environment lock

Every operation that changes an environment takes `<env dir>/.podship/lock` (a folder created with `mkdir`, with `owner.json`: who, what, since when) and releases it at the end. A second operation on the same environment fails and names the holder. `podship unlock` removes a lock left by a client that died. A console must take the same lock.

## Consoles and the operation protocol

A podship console runs operations on its own server, with its own deploy key, and streams the events back. The CLI talks to it when `--via console` is given, or when `transport: console` is set in `podship.yaml` (for the project or one environment). The console URL is `console.url` in `podship.yaml` or `PODSHIP_CONSOLE_URL`.

```
podship login https://console.example.com     # stores a personal access token (create it in the console)
podship whoami
podship deploy --env staging --via console
podship logout
```

Tokens live in the macOS Keychain, the Linux Secret Service, or `~/.config/podship/tokens.json` (mode 0600). In CI, set `PODSHIP_TOKEN`. If the console does not answer, the CLI says so and suggests `--via ssh` when your key has access to the server. A console rejects a token with 401 and a role that may not run the operation with 403 (exit code 3).

The protocol (version 1) is defined in `lib/src/protocol/protocol.dart`:

- `POST <console>/podship/v1/operations` with an `OperationRequest`: `{"protocol":1, "id", "operation", "project", "env", "params", "dry_run"}`. The answer is NDJSON: one `{"protocol":1, "request_id", "seq", "event": {…}}` per event, ending with a `result` event. Reads put their value in the result's `data.value`.
- `GET <console>/podship/v1/whoami`: the user and the roles.
- `GET <console>/podship/v1/operations`: the catalog (`podship operations --json` prints the same): every operation's stable name, whether it changes or destroys something, the typed confirmation it needs, and its parameters as JSON schema, ready for MCP tools.

- Operations that change DNS, tunnels, Access or SES have `"approval": "owner"` in the catalog (`domain.add`/`domain.remove`: `owner_if_cloudflare`) and name their `plan_operation` (`dns.plan`, `domain.plan`, `tunnel.plan`, `email.plan`, `app.plan`, `app.teardown.plan`). A plan returns `plan_id`. The apply runs only with `plan_id`, and only if the plan it computes again has the same id (otherwise nothing runs and the result names the new id). A request may carry `"origin": "cli" | "console" | "mcp"`; with `mcp`, these operations refuse to apply (`dry_run` and the plan operations work). So an MCP agent can plan; the owner approves the plan id in the console, which then sends the apply. `email.test` and `tunnel.create` have no plan: the console asks its usual confirmation.

`dispatch(Podship, OperationRequest)` runs a request and streams its events: a console can use it directly. Operation and parameter names are stable; new versions only add. The console itself is a separate project and is not part of this repository.

## podship console install

```
podship console install --host user@machine --hostname console.example.com \
  --image <console image> --admin you@example.com \
  [--tunnel-config ~/.cloudflared/config.yml --tunnel-service <unit or label> --tunnel-id <id>]
```

It writes a small project for the console (its `podship.yaml` and compose file), creates the console's deploy key on the machine (it never leaves it; the command prints the public key to authorize on servers with `podship access add console --key "<key>"`), and runs `link`, `secret init`, `deploy`, `domain add` and `backup schedule`.

## Cloudflare and SES

podship manages DNS records, tunnel routes, Access apps and the app's email sender through the Cloudflare API v4 and Amazon SES API v2. Every change is planned first, through read-only clients (a plan cannot change anything), and printed with before and after:

```
$ podship app setup --env staging --plan
Plan: app setup shop/staging on shop-vps (plan 3f2a9c1b04de)
  + registry           shop/staging
      after:  shop/staging on shop-vps: ports api=20001 web=20000
  + tunnel_ingress     tunnel 6ff4…: staging.shop.example
      after:  staging.shop.example ^/(api|v1)/ → http://localhost:20001; staging.shop.example → http://localhost:20000
  ~ dns_record         CNAME staging.shop.example
      before: CNAME staging.shop.example → 24fb…cfargotunnel.com (proxied)
      after:  CNAME staging.shop.example → 6ff4…cfargotunnel.com (proxied)
      note:   this record was not created by podship shop/staging
  + ses_identity       shop.example
      after:  domain identity shop.example in us-west-1 with Easy DKIM, tag podship=shop/staging
  + dns_record         DKIM CNAMEs of shop.example
      after:  3 × CNAME <token>._domainkey.shop.example → <token>.dkim.amazonses.com (the tokens come from SES when the identity is created)
Checks:
  ok TLS staging.shop.example: covered by the Universal SSL certificate of shop.example
  ok SES account (us-west-1): production access; 0 of 50000 sent in 24 h, 14/s
5 to create, 1 to update, 0 to delete, 0 unchanged.
```

Without `--plan`, podship prints the same plan and asks `Apply plan 3f2a9c1b04de (6 change(s))?`; `--yes` answers for CI, and `--plan-id 3f2a9c1b04de` applies only that exact plan. Changes run in order; if one fails, podship undoes the ones before it, newest first. The history record on the server holds the plan, what was applied, and how to undo each change. Running the same setup again gives an empty plan.

What podship touches, and what it leaves alone:

- It marks DNS records with the comment `podship <project>/<env>`, names Access apps `podship <project>/<env> <host>`, and tags SES identities `podship=<project>/<env>`.
- Removing deletes only DNS records that point to this environment (records that point elsewhere are reported and kept), only Access apps whose name starts with `podship `, and the SES identity only with `app teardown --email` and only when it carries this environment's tag (a domain identity is shared by every environment that sends from it).
- `app teardown` keeps the server registry entry; `podship destroy` removes the environment, and says to run `app teardown` first.
- Zones: each hostname goes to the longest zone it ends with among the zones the token can read; `dns.zone` must hold the hostname. No match is an error, never a guess.
- After an apply, `app setup` checks each name over DNS over HTTPS (`cloudflare-dns.com/dns-query`, so a stale negative answer in the local resolver does not matter) and fetches `health.public_url` with `curl --resolve` pinned to an edge address it got there.
- `podship status` shows DNS drift: a domain whose record points to another tunnel (or anywhere else) than the environment's, following a CNAME to the apex of the same zone (`www` → apex → tunnel).

### Configuration

```yaml
cloudflare:
  account_id: f037e56e89293a057740de681ac9abbe   # optional: default is the zone's account

environments:
  staging:
    proxy: {kind: cloudflare_tunnel, tunnel_id: 6ff42ae2-…}    # no config: → remotely managed
    dns:
      provider: cloudflare        # create the records through the API
      zone: shop.example          # optional
    domains:
      - host: staging.shop.example
        routes: [{path: "^/(api|v1)/", port: api}, {port: web}]
      - host: admin.staging.shop.example
        routes: [{port: web}]
        access: {emails: [you@shop.example], email_domains: [shop.example], session: 24h}
    email:
      from: "Shop <hola@shop.example>"
      region: us-west-1
      provider: ses
      identity: shop.example       # optional: the identity to create (default: the from domain)
      mail_from: bounce.shop.example   # optional: custom MAIL FROM, with its MX and SPF records
      env: {from: EMAIL_FROM, region: SES_REGION, provider: EMAIL_PROVIDER}   # the defaults
```

At deploy, podship gives the server container `EMAIL_FROM`, `SES_REGION` and `EMAIL_PROVIDER` (names from `email.env`). It never gives it podship's own AWS keys: the app's sending credentials are the app's secrets (`podship secret set`), ideally an IAM user that may only `ses:SendEmail` from its identity.

### Cloudflare API token

Create it in the Cloudflare dashboard: My Profile → API Tokens → Create Token → Custom token.

| Permission | Why |
|---|---|
| Zone · Zone · Read | Find the zone of a hostname (and its account). |
| Zone · DNS · Edit | Create, update and delete records. |
| Account · Cloudflare Tunnel · Edit | List tunnels, create one, and edit the ingress of remotely-managed tunnels. |
| Account · Access: Apps and Policies · Edit | Optional: only for `domains[].access`. |

Zone Resources: include the zones podship manages (all zones of the account, or specific ones). Account Resources: your account. A Universal SSL check (`/ssl/universal/settings`) also needs Zone · SSL and Certificates · Read; without it, the TLS check reports "could not check" and nothing else changes.

### AWS credentials for SES

An IAM user (or role) for podship, with this policy (narrow `Resource` to your identities' ARNs if you like):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ses:GetAccount", "ses:GetEmailIdentity", "ses:CreateEmailIdentity",
      "ses:DeleteEmailIdentity", "ses:PutEmailIdentityMailFromAttributes",
      "ses:TagResource", "ses:SendEmail"
    ],
    "Resource": "*"
  }]
}
```

### Where credentials live

`podship provider login cloudflare` and `podship provider login aws` (the access key id, then the secret) store them in the macOS Keychain, the Linux Secret Service, or `~/.config/podship/tokens.json` (mode 0600), as `provider:cloudflare` and `provider:aws`. In CI: `CLOUDFLARE_API_TOKEN`, and `AWS_ACCESS_KEY_ID` with `AWS_SECRET_ACCESS_KEY` (and `AWS_SESSION_TOKEN`). podship does not read `~/.aws` profiles. No credential is ever printed, logged, put in an event, or written to the history. A console passes its own encrypted store through `Integrations(secrets: …)`.

### First run (checklist)

Read-only first, then one live change on staging:

1. `podship provider login cloudflare`, then `podship provider check cloudflare`: the token is `active` and lists every zone podship will manage.
2. `podship provider login aws`, then `podship provider check aws --region us-west-1`: shows sandbox or production and the quota.
3. `podship tunnel list --env staging`: the environment's tunnel is marked `*`, with `remote` or `local` as expected.
4. `podship dns plan --env staging` and `podship status --env staging`: the plan and the drift match what you see in the dashboard.
5. `podship email status --env staging`: which identity lets the sender send, or what is missing.
6. `podship app setup --env staging --plan`: read the whole plan.
7. `podship app setup --env staging` and approve: the first live changes. Then `podship dns list --env staging` and `podship status --env staging` (drift: ok).
8. `podship email setup --env staging` if step 5 said it cannot send; DKIM verification takes minutes to hours. Then `podship email test --env staging` (to the SES mailbox simulator by default; with `--to`, a verified address while in the sandbox).
9. Only then, production: `podship app setup --env production --plan`, then apply.

To undo step 7: `podship app teardown --env staging --plan`, then apply.

Checked against recorded responses but not yet against the live APIs (look at the first real plan and result): the inline `policies` body of an Access app create; the `source` field of a newly created remote tunnel's configuration; `Tags` in `GetEmailIdentity`; MX `priority` and TXT quoting as Cloudflare returns them.

## Moving from hand-written scripts

See [docs/migrating-from-scripts.md](docs/migrating-from-scripts.md). It uses a real production setup as the example.

## Tests

Run the unit tests with `dart test -t unit`, or `dart run tool/test.dart` (it prints a short result and keeps the full log in the temp folder). Agents whose hooks block `dart test` use `dart run tool/test.dart` or the very_good_cli MCP `test` tool (`dart: true`, tags `unit`). The tags are in `dart_test.yaml`. The tests cover the config parser, file selection, release ids and retention, the server registry, plans, the `.env` and `passwords.yaml` editors, tunnel and Caddy routes, the server agent (`agent_test.dart`: the settings file, retention and ISO weeks, the backup, the drill and the restore with a fake process runner, and the real process pipes), the operation protocol, events, test output parsing, the compose override (replicas, Redis, egress), the input hashes and the reuse of web builds and test results (`inputs_test.dart`, with a real temporary git repository), the notifications (`notify_test.dart`: the watcher, the channels against recorded responses and a fake process runner, the HMAC signature), and the scheduler (`scheduler_test.dart`: due computation across a DST change and a missed night, the tick with a fake backup script, the idempotent launchd install with a stubbed `launchctl`, the import of per-environment agents, and `backup schedule` writing the registry without `launchctl` or `systemctl`).

The Cloudflare and SES integrations are tested against recorded API responses in `test/api_fixtures/` (`cloudflare_test.dart`, `ses_test.dart`, `zones_test.dart`, `changes_test.dart`, `app_test.dart`): every client call, SigV4 against AWS's published test vectors, plan rendering and plan ids, idempotency, rollback, zone resolution (including the zone of the owner's real account), drift, the approval rules of the protocol, and the CLI wiring. They never reach the network.

The integration test in `test/integration/flow_test.dart` deploys a small project to a real Docker host over ssh: a deploy, a failed deploy with automatic rollback, `rollback`, `rollback --to`, a backup, a drill, a restore, `env set`, `promote`, `status` and `destroy`. It runs only when `PODSHIP_IT_HOST` is set: `dart test -t integration`, or `dart run tool/test.dart integration` for a short log.

## License

MIT. Copyright (c) 2026 Federico Ramallo.
