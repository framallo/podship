# Server (resources, registry, bootstrap)

Status: draft 2026-10-06. Mockups: `mockups/web-server.html` (7 states), `mockups/web-new-server.html` (6 states). Provider facts: `decisions/2026-10-06-providers-first-run-mcp.md`. Copy: `copy/servers.md`.

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

## 8b. Provider info, projects and destroy (added 2026-10-06)

- **Provider panel** (Hostinger servers): VPS id, plan (`KVM 4`), data center (city, country), IPv4, OS template, created, subscription renews or ends on, auto-renewal on/off, Hostinger weekly backups on/off, "Open in hPanel". Servers added over SSH show "Added over SSH (no provider)".
- **Projects on it**: the registry table (already above) with links.
- **Destroy** (web-server 6 and 7): blocked while environments are registered ("Move or destroy these environments first: shop/production, shop/staging") with links to `podship destroy` per environment; when empty, tier 2 typed with the server alias (`shop-vps`). The dialog states what happens, in order: remove the SSH alias and the console's registry entry, delete the Cloudflare Tunnel, stop the VPS, turn off auto-renewal. And the limit: "Hostinger's API can't delete a VPS. It stays stopped and billed until 3 Nov 2026, then Hostinger removes it. To delete it sooner, use hPanel."

## 8c. New server (`/servers/new`, `mockups/web-new-server.html`)

| Step | Content | Frame |
|---|---|---|
| 1. How | "Create a VPS on Hostinger" or "Add a server I already have" (SSH) | 1 |
| 2. Configure | Name (SSH alias, `^[a-z0-9-]+$`), data center (from the API, grouped by continent; Mexico first when available, otherwise the note), plan (from the catalog: CPU, memory, disk, price per month), OS (Ubuntu 24.04 LTS default; podship bootstrap supports Debian and Ubuntu), SSH keys (the console's own key is always added; pick people's keys), firewall (preset "SSH only, web through the tunnel" or "SSH, HTTP and HTTPS for Caddy"), Cloudflare Tunnel (on by default when Cloudflare is connected), Hostinger weekly backups (off by default: podship backs up the data) | 2 |
| 3. Review | Summary and price; tier 1; the button carries the price | 3 |
| 4. Provisioning live | Operation view: Hostinger steps, bootstrap steps, tunnel, registration | 4 |
| 5. Registered | The server page with "Ready for projects" and the next step (`podship link` from a project, or `launch`) | 5 |
| Failed | "Hostinger couldn't set up the VPS: the plan isn't available in São Paulo right now. Nothing was charged." or, after purchase, "The VPS exists (id 1084213) but bootstrap failed at Install Docker. Retry bootstrap" (bootstrap is safe to run again) | 6 |

## 9. Open questions

Prices and data centers come from Hostinger at run time; the mockup values are examples. Other providers (Hetzner, DigitalOcean) use the same flow with their own pickers. (owner)
