# Spec · Server (resources, registry, bootstrap, new server)

Status: draft 2026-10-06. Key: SRV. Copy: [servers](../copy/servers.md). Mockups: `mockups/web-server.html` (7 states), `mockups/web-new-server.html` (6 states). Decisions: [providers](../decisions/2026-10-06-providers-first-run-mcp.md), [rationale](../decisions/2026-10-07-spec-servers-rationale.md).
Read: a capacity and placement page, desktop, technical, medium restraint.

## Server page

### Server page: Purpose

The owner sees what runs on a server, its free resources, ports and backup slots, to place environments safely (J8).

### Server page: Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | Sidebar Servers, overview group row, server name in the environment band | |
| Exit | An environment, the operation view (bootstrap), Settings → SSH access for this server | |

### Server page: States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| Linux | caza-vps | Linux server | web 1 |
| macOS | agentes.local, macOS arm64, launchd, Docker Desktop. Note `server.macNote`. | macOS server | web 2 |
| Bootstrap plan | Tier 1. Steps of `server bootstrap` on Debian/Ubuntu: Docker and compose, age, zstd, firewall rules, podship folders. "Safe to run again". | podship folders missing | web 3 |
| Unreachable | Danger banner `server.unreachable`, "Try again", and the SSH command to test (`server.test`) | SSH fails ([COM-server-unreachable](common.md#com-server-unreachable)) | web 4 |
| Destroy blocked | `destroy.blocked` with a `podship destroy` link per environment | Environments are registered | web 6 |
| Destroy | Tier 2, typed with the server alias (`shop-vps`). Steps `destroy.steps` in order, then `destroy.limit`. | No environments | web 7 |

### Server page: Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| SRV-1 | ui | No primary when bootstrapped. Primary `server.bootstrap` when podship's folders are missing. | |
| SRV-2 | data | Sources: `podship server status`, `projects list`, `doctor`. | |
| SRV-3 | data | Header: host alias (`caza-vps`), `server.about` ("Ubuntu 24.04, x86_64, Docker 28.4, compose 2.39"), scheduler (systemd or launchd). | |
| SRV-4 | data | Header also: podship home (`/srv/podship`), proxy (Cloudflare Tunnel `cazafacturas-vps`). | |
| SRV-5 | data | Resources: CPU (load, cores), memory used/total, disk used/total with the backup folder size. Each as numbers and a bar. | |
| SRV-6 | data | Disk: warn above 80 %, danger above 90 %. | |
| SRV-7 | data | Registry table: project/env, compose project, directory, ports (name, number), domains, database, backup unit and slot, updated. | |
| SRV-8 | data | Containers per environment: name, state, CPU %, memory. | |
| SRV-9 | data | Port range and free ports: "20000–20999, 6 in use". Backup slots: 03:00 cazafacturas/production, 03:15 shop/production, 03:30 shop/staging. | |
| SRV-10 | data | Provider panel (Hostinger): VPS id, plan (`KVM 4`), data center (city, country), IPv4, OS template, created. | |
| SRV-11 | data | Provider panel also: renews or ends on, auto-renewal on/off, Hostinger weekly backups on/off, `server.provider.hpanel`. | |
| SRV-12 | data | Servers added over SSH show `server.provider.none`. Projects on the server: the registry table with links. | |
| SRV-13 | flow | Destroy steps, in order: remove SSH alias and registry entry, delete the Cloudflare Tunnel, stop the VPS, turn off auto-renewal. | |
| SRV-14 | flow | The destroy dialog states the limit: Hostinger's API can't delete a VPS. It stays stopped and billed until Hostinger removes it, for example 3 Nov 2026 (`destroy.limit`). | |
| SRV-15 | ui | Components: `DefinitionList`, `UsageBar` (with text value), `DataTable`, `Banner`, `ConfirmDialog`, `ProviderPanel`. | |
| SRV-16 | test | Registry rows match `projects list`. | |
| SRV-17 | test | Disk above 90 % appears on the overview attention list. | |

## New server

### New server: Purpose

The owner creates a Hostinger VPS or adds an existing SSH server at `/servers/new`, and it ends registered and bootstrapped.

### New server: Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | `/servers/new` (`server.new`) | |
| Exit | The server page with `new.ready` and `new.ready.next` | Registered |

### New server: States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| How | `new.how.create` or `new.how.existing` (SSH) | Step 1 | 1 |
| Configure | SRV-18 to SRV-23 | Step 2 | 2 |
| Review | Summary and price. Tier 1. The button carries the price (`new.buy`). | Step 3 | 3 |
| Provisioning | Operation view: Hostinger steps, bootstrap steps, tunnel, registration | Step 4 | 4 |
| Registered | Server page, "Ready for projects", next step `podship link` from a project, or `launch` | Step 5 | 5 |
| Failed before purchase | `new.failed.before` ("the plan isn't available in São Paulo right now") | Hostinger refuses | 6 |
| Failed after purchase | `new.failed.after` ("id 1084213", "Install Docker") with `new.failed.retry`. Bootstrap is safe to run again. | Bootstrap fails | 6 |

### New server: Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| SRV-18 | validation | Name: SSH alias, `^[a-z0-9-]+$`. | |
| SRV-19 | data | Data center: from the API, grouped by continent. Mexico first when available, otherwise `new.dc.noMexico`. | |
| SRV-20 | data | Plan from the catalog: CPU, memory, disk, price per month. OS: Ubuntu 24.04 LTS default. Bootstrap supports Debian and Ubuntu. | |
| SRV-21 | data | SSH keys: the console's own key is always added. The owner picks people's keys. | |
| SRV-22 | data | Firewall presets: `new.firewall.tunnel` or `new.firewall.caddy`. | |
| SRV-23 | data | Cloudflare Tunnel: on by default when Cloudflare is connected. Hostinger weekly backups: off by default. | [rationale](../decisions/2026-10-07-spec-servers-rationale.md) |

## Copy keys

`server.*`, `new.*`, `destroy.*` in the copy table.

## Accessibility and platform

| ID | Rule |
|---|---|
| SRV-24 | Usage bars are not the only cue. The number and the word ("Disk 61 % used, 78 GB free") are in the text and the label ([COM-status-not-color](common.md#com-status-not-color)). |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Prices and data centers come from Hostinger at run time. Mockup values are examples. Other providers (Hetzner, DigitalOcean) use the same flow with their own pickers. | owner | 2026-10-06 |
