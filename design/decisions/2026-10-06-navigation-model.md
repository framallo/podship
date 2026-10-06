# Navigation model

Status: proposed 2026-10-06. Decided by: designer.

## Context

The data is a tree: servers host environments; projects own environments; an environment has releases, backups, variables, domains, logs and a database. Most jobs start from a project's environment (deploy, rollback, backups). Some start from a server (capacity, bootstrap, access). Everything ends in an operation.

## Options

1. **Project-first (chosen).** Sidebar lists projects and their environments; servers are a second section. URLs: `/projects/<project>/<env>/<tab>`. Matches how the owner thinks ("roll back cazafacturas production") and how the CLI addresses things (`--env production` inside a project).
2. Server-first. Mirrors the registry, but the owner would have to remember which server hosts staging before every deploy (recall over recognition).
3. A flat list of environments with filters. Fast to scan with few projects, but loses the project grouping that promote and copy-secrets depend on.

## Decision

Routes (English, stable, routable on web):

| Route | Screen |
|---|---|
| `/overview` | All servers, projects and environments with health, current release, last backup age |
| `/projects/<p>/<env>` | Environment: releases (default tab) |
| `/projects/<p>/<env>/backups`, `/variables`, `/domains`, `/logs`, `/database` | Environment tabs |
| `/operations/<id>` | Live or finished operation |
| `/servers/<host>` | Server: resources, registry, bootstrap |
| `/history` | All operations, filterable |
| `/settings/people`, `/settings/access`, `/settings/ci` | Settings |

Shell by window width (never by device):

- **Expanded (≥840):** sidebar 240 px: Overview, then a "Projects" group (each project expands to its environments), a "Servers" group, then History and Settings. Top bar: breadcrumbs, the command palette (`Ctrl K` / `⌘ K`), the running-operations indicator, the account menu. Content uses two columns on the environment page (main 1fr, side 340 px).
- **Medium (600–839):** navigation rail with Overview, Projects, Servers, History, Settings; one pane.
- **Compact (<600):** bottom navigation with 4 destinations: Overview, Operations (running and recent), Servers, Settings. Projects are reached from Overview (each environment is a row). The environment page shows tabs as a scrollable tab bar.

The **environment band** sits under the top bar on every environment-scoped page: production in inverse ink with a lock icon, other environments in a hairline band. The band names the environment, the server and the current release, so the target of every action is visible before the action.

Keyboard (expanded): `Ctrl K` palette lists every command ("Deploy cazafacturas to staging", "Roll back cazafacturas production…"); `G O` overview, `G H` history; `?` lists shortcuts. No single-key shortcut ever starts an operation on production; the palette opens the same confirmation as the button.

## Consequences

Promote and copy-secrets pick the source environment inside the same project. The phone has no project list destination; with more than about 8 environments the overview gets a filter field.
