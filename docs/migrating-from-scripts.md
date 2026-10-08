# Moving from hand-written scripts

Many Serverpod projects reach production with a few shell scripts: one that builds and starts the compose project, one that edits the reverse proxy, one that takes backups, one that restores them. This guide moves such a setup to podship without stopping production. The example is CazaFacturas, a Serverpod app with a Flutter app, an admin panel, and two sidecars.

## The starting point

CazaFacturas ran on one VPS with these pieces:

| Piece | What it did |
|---|---|
| `ops/desplegar.sh` | Built the two Flutter web apps on the laptop, ran `git pull` on the server, copied the web builds with rsync, ran `docker compose build` and `up -d` on the server, and checked `/salud` through the public URL. |
| `ops/vps-bootstrap.sh` | Checked out the repository on the server and generated `passwords.yaml` and `.env`. |
| `ops/cortar.sh` | Edited the Cloudflare Tunnel config and restarted `cloudflared`. |
| `ops/respaldo.sh` + a systemd timer | Daily `pg_dump -Fc`, a SQLite-safe copy of a sidecar volume, row counts, checksums, an age-encrypted copy, and retention. |
| `ops/restaurar.sh` | A restore drill in a throwaway container, and a production restore that renamed the old database. |
| `ops/traer-respaldos.sh` + a launchd agent | Pulled the encrypted copies to the owner's Mac. |

It worked, but it had gaps:

- **No rollback.** A bad deploy meant a fix and another deploy. The compose file tagged every image `:production`, so the previous image was gone after each build.
- **No automatic health gate.** The script checked health after the switch and only printed a message.
- **One environment.** A staging copy with the same compose file would build images with the same `:production` tags and overwrite the production images.
- **Deploys came from the server's git checkout,** not from a known commit on the laptop. The web builds came from the laptop's working tree, uncommitted changes included.

## Step 1: describe production as it runs

Write `podship.yaml` so that it matches the running setup exactly. For CazaFacturas:

```yaml
project: cazafacturas
server_package: cazafacturas_server
build:
  flutter_web:
    - {name: app, path: cazafacturas_flutter, output: cazafacturas_server/web/app, base_href: /app/}
    - {name: admin, path: cazafacturas_admin, output: cazafacturas_server/web/admin, base_href: /admin/}
  files:
    - "!cazafacturas_server/web/app/**"    # .gitignore excludes the web builds; ship them
    - "!cazafacturas_server/web/admin/**"
compose:
  files: [docker-compose.prod.yml]         # the existing file, unchanged
  build_contexts:
    pacewright: /srv/pacewright            # the compose file said ../pacewright
  remote_pre_build:
    - git -C /srv/pacewright pull -q --ff-only
environments:
  production:
    host: caza-vps
    dir: /srv/cazafacturas-serverpod       # the existing checkout
    compose_project: cazafacturas          # the existing project name keeps the volumes
    ports: {api: 8086, web: 8087}
    secrets:
      env_file: .env                       # where the secrets already are
      passwords_file: cazafacturas_server/config/passwords.yaml
    health:
      url: http://127.0.0.1:{port:web}/health
      fallback_urls: ["http://127.0.0.1:{port:web}/salud"]
```

Three details matter:

- **Keep the compose project name.** Docker names volumes `<project>_<volume>`. With the same name, podship's releases use the same database volume.
- **Point the secrets at their current files.** podship links them into each release. Nothing moves.
- **Relative build contexts that point outside the repository** (`../pacewright`) must become absolute in `build_contexts`, because each release lives in its own folder.

The old releases served the health route at `/salud`; the new code serves `/health` and keeps `/salud` as an alias. `fallback_urls` lets a rollback to an old release pass the health check.

Run `podship doctor --env production`. It checks ssh, Docker, disk, ports and DNS, and it does not count the ports of the running compose project as taken.

## Step 2: adopt the running setup

```
podship adopt --env production --dry-run
podship adopt --env production
```

`adopt` restarts nothing. It copies the current checkout (without `.git` and the secrets) into `releases/<time>-<commit>-adopted`, tags the images of the running containers with that release id, links the secrets, and points `current` at it. From now on, `podship rollback --env production` can always come back to the setup that ran before podship.

## Step 3: deploy with podship

```
podship deploy --env production --dry-run
podship deploy --env production
```

The dry run prints every step. The real deploy exports the commit, builds the web apps from that commit, uploads the selected files, builds the images on the server with tags like `cazafacturas-server:<release>`, backs up the database, switches, checks health, and switches back by itself if the check fails.

Then prove the rollback path in both directions:

```
podship rollback --env production                  # back to the adopted release
podship rollback --env production --to <release>   # forward again
```

## Step 4: move the backups

podship's backup script does what the old one did, with configurable names. Point `backup` at the old settings, and list the old timer in `replaces`, so the server never runs two schedules:

```yaml
    backup:
      dir: /srv/backups/cazafacturas
      unit: podship-backup-cazafacturas
      replaces: [cazafacturas-respaldo]
      schedule: "*-*-* 03:30:00 America/Mexico_City"
      recipients: [~/.ssh/id_ed25519.pub, ~/.ssh/id_rsa.pub]
      volumes:
        - {name: pacewright, volume: cazafacturas_pacewright, sqlite: [pacewright.db], files: [secrets.json, config.toml]}
      layout: {dump: cazafacturas.dump}
      stop_on_restore: [server, chrome, pacewright]
      offsite:
        dir: ~/Sync/Backups/cazafacturas/encrypted
        identities: [~/.ssh/id_ed25519, ~/.ssh/id_rsa, ~/Sync/Backups/cazafacturas/clave-privada-age.txt]
```

```
podship backup schedule --env production --dry-run
podship backup schedule --env production
podship backup now --env production
podship backup drill --env production
podship backup pull --env production
```

New backups go to `daily/` and `encrypted/`. The old folders stay where they are, and you can still read them. The new encrypted copies use the owner's SSH keys as age recipients, so there is no separate age key to keep safe. The old age identity stays in `offsite.identities` only to read the old archives.

`podship backup pull --env production --schedule` writes the pull job into this machine's registry; `podship scheduler install` registers the one agent that runs it (and retires the old launchd agent).

## Step 5: add staging

Staging is one more environment in the same file. CazaFacturas runs it on another machine, a Mac with Docker Desktop:

```yaml
  staging:
    host: agente@agentes.local
    dir: /Users/agente/podship/cazafacturas-staging
    podship_home: /Users/agente/podship
    remote_path: /opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin
    compose_files: [ops/podship/staging.compose.yml]
    ports: {api: auto, web: auto}
```

`compose_files` adds a small compose file for staging only: the public host names and lower resource limits. Then:

```
podship link --env staging
podship secret init --env staging        # fresh secrets, a new master key
podship secret copy --from production AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY --env staging
podship deploy --env staging --no-public-check
podship domain add --env staging
```

## Step 6: retire the scripts

Move the old scripts to `ops/legacy/` and keep them for one release, in case you must go back. Replace the task-runner recipes with podship commands:

| Before | After |
|---|---|
| `ops/desplegar.sh` | `podship deploy --env production` |
| `ops/desplegar.sh --sin-web` | `podship deploy --env production --skip-web` |
| `docker compose … ps` over ssh | `podship status --env production` |
| `docker compose … logs -f server` over ssh | `podship logs --env production --follow --service server` |
| `systemctl start cazafacturas-respaldo` | `podship backup now --env production` |
| `restaurar.sh --simulacro` | `podship backup drill --env production` |
| `restaurar.sh --produccion` | `podship backup restore --env production` |
| `ops/traer-respaldos.sh` | `podship backup pull --env production` |
| `ops/cortar.sh` | `podship domain add --env production` |
| (nothing) | `podship rollback --env production` |
