# podship console: design

Purpose: the product design of **podship console**, the web and phone UI that runs podship's operations (deploy, rollback, promote, backups, secrets, domains, logs, servers, access) through podship's library and shows each operation live.
Status: draft, in review since 2026-10-06. Nothing here is built yet.

## Reading this as

An operator console for one technical owner, at a desk most of the time and on a phone when something breaks: calm, exact, high restraint; dense on desktop, one question per screen on the phone. Color means state and nothing else.

## Stack

A product surface: **Flutter on its own design system, backed by a Serverpod server** that links podship as a library and runs the operations. English URLs (`/overview`, `/projects/cazafacturas/production/backups`). Default language English, Spanish second (`decisions/2026-10-06-default-language.md`).

## What is here

| Folder | Content |
|---|---|
| `research/` | `job-stories.md` (from the owner's brief, not interviews), `assumptions.md` (the interview, answered from the brief, as an assumption map) |
| `decisions/` | default language, navigation model, dangerous actions, live-stream model, visual direction, CLI through the console, providers + first run + MCP |
| `specs/` | one spec per screen group, plus `design-system.md` (tokens and components for Flutter) |
| `copy/` | `glossary.md`, `common.md`, one copy table per screen group (key, en, es, notes) |
| `mockups/` | the viewer's files: `mockups.json`, `podship.css` (tokens), the brand board, 10 desktop pages, 2 phone flows |
| `comentarios/` | the reviewer's comments, written by the viewer (`index.md`) |
| `audits/` | empty until the first build is reviewed |

## Locked count (what this round delivers)

Decisions: 7. Specs: 15 (10 screen groups, test stage, CLI and tokens, first-run setup, MCP, design system). Copy: 16 files (glossary, common, 14 screen groups).

Added during the round on request: the test stage and production test gate (`specs/tests.md`); the CLI through the console with tokens, origins and the lock (`specs/cli-and-tokens.md`); new servers through a provider and server destroy (`specs/servers.md`), first-run setup (`specs/first-run.md`) and MCP access (`specs/mcp.md`).

Mockups: 1 brand board (3 panels), 13 desktop pages at 1440 px with 79 states, 2 phone flows at 390 px with 8 main frames and 10 alternates.

| File | States or frames |
|---|---|
| `brand.html` | 1 direction A, light; 2 direction A, dark; 3 direction B (rejected), same fragment |
| `web-overview.html` | 1 ideal; 2 a production environment unhealthy and a backup too old; 3 data stale (console server unreachable); 4 first run (no servers); 5 dark |
| `web-environment.html` | 1 production, releases with test badges (ideal); 2 deploy to production, confirm; 3 roll back production, confirm; 4 production unhealthy, roll back is the primary action; 5 lock held by a CLI operation, actions locked; 6 staging, promote blocked by CPU architecture; 7 database tab; 8 collaborator (read only on production); 9 force release the lock (owner, typed) |
| `web-operation.html` | 1 deploy running, started from the CLI (origin label); 2 deploy failed, automatic rollback; 3 deploy succeeded; 4 reconnecting; 5 dark, running |
| `web-backups.html` | 1 list, schedule, off-site, last drill; 2 drill finished; 3 restore, choose a backup; 4 restore, typed confirmation; 5 restore finished, how to undo; 6 no schedule yet (empty) |
| `web-variables.html` | 1 variables and secrets; 2 set a secret; 3 restart needed; 4 copy secrets from another environment |
| `web-domains.html` | 1 domains; 2 add a domain, DNS record; 3 DNS not pointing yet |
| `web-logs.html` | 1 following; 2 paused, filtered, search match; 3 no lines in range |
| `web-server.html` | 1 caza-vps (provider, resources, registry); 2 agentes.local (macOS, no provider); 3 bootstrap plan; 4 server unreachable; 5 MCP-started operation on the server's activity (origin); 6 destroy blocked by environments; 7 destroy an empty server, typed |
| `web-new-server.html` | 1 how to add; 2 configure (data center, plan, OS, keys, firewall, tunnel); 3 review and buy; 4 provisioning and bootstrap live; 5 registered; 6 bootstrap failed after purchase |
| `web-first-run.html` | 1 owner; 2 remote access (Cloudflare Tunnel); 3 token missing a permission; 4 provider token tested; 5 first server; 6 done; 7 setup link already used |
| `web-history.html` | 1 all operations with origin column and filter (Console, CLI, CI, MCP, CLI over SSH); 2 one operation expanded; 3 filtered by origin, no results |
| `web-settings.html` | 1 people and roles per project or environment; 2 SSH access per server; 3 CI deploy key created (shown once); 4 remove access, typed confirmation; 5 access tokens; 6 create a token; 7 token shown once; 8 CI tokens for a project; 9 revoke a token; 10 authorize the CLI (`podship login`); 11 MCP page (connect Claude Code, tools, rules); 12 create an MCP token; 13 approval request from an agent |
| `web-tests.html` | 1 test stage running; 2 deploy blocked by failing tests; 3 skip tests on staging (reason); 4 skip tests on production (reason + typed); 5 promote with the release's test status; 6 promote refused, tests not passed; 7 project test suites; 8 edit a suite, validation errors |
| `status-phone.html` | main: 1 overview, 2 environment, 3 backups. Alternates: overview loading, overview stale, overview dark, environment backup failed |
| `rollback-phone.html` | main: 1 overview (production unhealthy), 2 environment, 3 confirm, 4 rolling back, 5 healthy again. Alternates: choose another release, confirm in Spanish, reconnecting, rollback failed, collaborator cannot roll back production, confirm dark |

Example data: the projects `cazafacturas` (real config in the CazaFacturas repo) and `shop` (the README example), the servers `caza-vps` (Linux x86_64) and `agentes.local` (macOS arm64). Release ids, sizes, times and people are examples.

## How to view the mockups

podship is not a Serverpod project, so the mockups run on the viewer's CLI:

```
dart pub global activate --source git https://github.com/framallo/mockup_viewer.git --git-path packages/mockup_viewer
cd /Users/framallo/work/podship
mockup_viewer --dir design/mockups --comments design/comentarios --port 8101 --open
```

Then open http://localhost:8101/. To share: `cloudflared tunnel --url http://127.0.0.1:8101` (the URL changes every session). Desktop pages open from the "Web" group. The HTML files also open directly in a browser.

## Who reviews

The owner (Federico Ramallo). Comments go to `comentarios/index.md`; each round answers every comment with a change or a reason.
