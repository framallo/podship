# Server (resources, registry, bootstrap)

Status: draft 2026-10-06. Mockups: `mockups/web-server.html` (4 states). Copy: `copy/servers.md`.

Reading this as: a capacity and placement page, desktop, technical, medium restraint.

## 1. Job story

J8: see what runs on each server, its free resources and the ports and backup slots in use, so a new environment goes in safely.

## 2. Entry and exits

Entry: sidebar Servers; overview group row; the environment band's server name. Exits: an environment; operation view (bootstrap); Settings → SSH access for this server.

## 3. Primary action

None when bootstrapped. "Bootstrap this server" when podship's folders are missing.

## 4. Content (`podship server status`, `projects list`, `doctor`)

- Header: host alias (`caza-vps`), what it is ("Ubuntu 24.04, x86_64, Docker 28.4, compose 2.39"), scheduler (systemd or launchd), podship home (`/srv/podship`), proxy (Cloudflare Tunnel `cazafacturas-vps`).
- Resources: CPU (load and cores), memory used/total, disk used/total with the backup folder's size, each as numbers and a bar with the value in text; warn above 80 % disk, danger above 90 %.
- Registry table: project/env, compose project, directory, ports (name and number), domains, database, backup unit and slot, updated.
- Containers per environment: name, state, CPU %, memory.
- Port range and free ports: "20000–20999, 6 in use".
- Backup slots: 03:00 cazafacturas/production, 03:15 shop/production, 03:30 shop/staging.

## 5. States

| State | Frame |
|---|---|
| caza-vps, Linux | web 1 |
| agentes.local, macOS arm64, launchd, Docker Desktop; note "Staging and non-critical apps" | web 2 |
| Bootstrap plan (tier 1): the steps `server bootstrap` runs on Debian/Ubuntu: install Docker and compose, age, zstd, firewall rules, podship folders; "Safe to run again" | web 3 |
| Unreachable: danger banner "Can't reach caza-vps over SSH since 09:41 (connection timed out). Environments on it show last known values." + "Try again" and the SSH command to test | web 4 |

## 6. Components

`DefinitionList`, `UsageBar` (with text value), `DataTable`, `Banner`, `ConfirmDialog`.

## 7. Accessibility

Usage bars are not the only cue: the number and the word ("Disk 61 % used, 78 GB free") are in the text and the label.

## 8. Acceptance criteria

Registry rows match `projects list`; disk above 90 % appears on the overview's attention list.

## 9. Open questions

Adding a new server from the console (alias, user, key) or only via `~/.ssh/config` on the console host? Proposed: read `~/.ssh/config`, add from the CLI. (owner)
