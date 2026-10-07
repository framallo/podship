# Spec · Environment (releases, deploy, promote, rollback, database)

Status: draft 2026-10-06. Key: ENV. Copy: [environment](../copy/environment.md), [common](../copy/common.md). Mockups: `mockups/web-environment.html`, `mockups/rollback-phone.html` frames 2–3, `mockups/status-phone.html` frame 2. Decisions: [dangerous actions](../decisions/2026-10-06-dangerous-actions.md), [rationale](../decisions/2026-10-07-spec-environment-rationale.md).
Read: owner at a desk (ship) or phone (emergency). Exact, careful, highest restraint on production.

## Purpose

The owner ships, promotes and rolls back one environment. A production rollback takes four taps and never happens by accident (J2, J3, J9).

## Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | Overview row, sidebar, palette ("Deploy cazafacturas to staging"), `/projects/<p>/<env>` | |
| Exit | `/operations/<id>` | Any operation starts |
| Exit | Tabs (backups, variables, domains, logs, database), server page (server name) | |

## States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| Healthy, non-production | Primary `env.action.deploy`. Secondary: `env.action.restart`, `env.action.rollback`. | Health check passes | |
| Healthy, production | Primary `env.action.promote` if staging runs a newer release on a compatible server, else `env.action.deploy`. Secondary: the other one, Restart, Roll back. | Health check passes | web 1 |
| Deploy dialog | Tier 1: ref, commit, plan steps, consequence | Deploy | web 2 |
| Rollback dialog | Tier 1: target preselected, `rollback.dialog.other`, database note | Roll back | web 3 |
| Unhealthy | Danger banner `env.unhealthy.banner`. Primary `env.action.rollbackTo` the previous `ok` release. Secondary: Deploy, Restart, "Open logs". | Health check fails | web 4, rollback-phone 2 |
| Operation running | Run banner with step and link. No primary. Mutating actions disabled with reason ([COM-lock](common.md#com-lock)). Secondary `lock.open`. | Operation on this environment | web 5 |
| Promote blocked | `promote.blocked.arch` with `promote.blocked.action` | Servers differ in CPU architecture | web 6 |
| Database tab | ENV-10 | Tab | web 7 |
| No permission | Read only. No primary. Actions disabled with `env.readOnly`. | Collaborator | web 8, rollback-phone alt "collaborator" |
| Loading | Band and timeline skeletons ([COM-loading](common.md#com-loading)) | First load | |
| Not found | `state.notFound` | Unknown environment | |
| Server unreachable | Band says "Can't reach caza-vps". Last known release marked stale. All actions disabled with `state.serverUnreachable`. | SSH fails ([COM-server-unreachable](common.md#com-server-unreachable)) | server state 4 banner |
| Phone | Status, rollback confirm sheet, choose another release | Compact | status-phone 2, rollback-phone |

## Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| ENV-1 | ui | Every state has exactly one filled button, except running and no permission, which have none. | |
| ENV-2 | layout | Tabs: Releases, Backups, Variables, Domains, Logs, Database. Expanded: two columns, side column 340. | web 1 |
| ENV-3 | data | Current release: id, commit first line, ref, who, when, duration, where images were built, health URLs and last answer. | |
| ENV-4 | data | Releases: timeline, newest first. Row: id (mono), status pill, test badge, deployed by, age, origin, row menu. | [tests](tests.md) |
| ENV-5 | data | Origin: deploy, promote from staging, rollback, adopt. Row menu: `env.releases.menu.rollback`, `env.releases.menu.copy`, "Open operation". | |
| ENV-6 | data | Side column: Health (server URL, public URL, last check), Last backup (age, size, "Back up now"). | |
| ENV-7 | data | Side column: Staging (release, promote state), Recent activity (3 rows, link to history). | |
| ENV-8 | layout | Medium: one column, side column as a section under the header. | |
| ENV-9 | layout | Compact: band, title, health line, scrollable tabs, manifest as a list. The primary is full width above the nav. | |
| ENV-10 | data | Database tab: engine, size, mode (per environment or shared), migrations applied vs newest in the release, database users. | |
| ENV-11 | data | Connect commands: `podship db connect --env production`, `podship tunnel`. | |
| ENV-12 | ui | Components: `EnvironmentBand`, `HealthIndicator`, `StatusPill`, `ReleaseTimeline`, `ConfirmDialog`/`ConfirmSheet`, `TypedConfirmField`, `Banner`, `Tabs`, `DataTable`, `Menu`, `CodeText`. | [design system](design-system.md) |
| ENV-13 | ui | Tokens: `inverse`/`onInverse` production band, `run` running banner, `danger` unhealthy. Focus ring is `onInverse` inside the band. | |
| ENV-14 | ui | Confirm labels carry verb, environment and target: `deploy.dialog.confirm`, `promote.dialog.confirm`, `rollback.dialog.confirm`. | |
| ENV-15 | ui | Consequence lines: `deploy.dialog.consequence`, `rollback.dialog.consequence`. | |
| ENV-16 | validation | Ref defaults to `build.ref`. Confirm stays disabled until the ref resolves (`deploy.dialog.resolved`). Unknown ref: `deploy.dialog.refError` on blur. | |
| ENV-17 | flow | Option `deploy.dialog.skipBackup`: off on production. Turning it on needs the tier-2 typed string. | |
| ENV-18 | flow | Option "Skip the public URL check". | |
| ENV-19 | flow | Rollback target default: newest `ok` release that is not current. `failed` releases show `env.releases.failedNote`. | |
| ENV-20 | flow | `rollback.dialog.withDb` makes the dialog tier 2: backup picker plus typed field. | |
| ENV-21 | flow | Backup default: the one taken before the current release's deploy. | |
| ENV-22 | flow | Promote needs the same CPU architecture on both servers. podship refuses otherwise. | |
| ENV-23 | flow | The promote dialog shows the release's test result. Production refuses a release whose tests did not pass. | [tests](tests.md) |
| ENV-24 | flow | With suites configured, deploy runs tests first. A failing suite blocks before build or upload. | [tests](tests.md) |
| ENV-25 | flow | One operation per environment. | [COM-lock](common.md#com-lock) |
| ENV-26 | flow | After confirm the operation view opens. On the phone it replaces the sheet. | |
| ENV-27 | test | No mutating action on production starts without a dialog: button, palette or row menu. | |
| ENV-28 | test | Phone, production unhealthy, 390 × 844: rollback starts in 4 taps, no typing. | |
| ENV-29 | test | The 4 taps: app icon, production row, `env.action.rollbackTo`, `rollback.dialog.confirm`. | |
| ENV-30 | test | Keyboard only: Tab reaches "Roll back to …". Enter opens the dialog on Cancel. A second Enter cancels. | [COM-dialog](common.md#com-dialog) |
| ENV-31 | test | Goldens: 8 web states, 2 phone frames, light and dark, 200 % text on the compact rollback sheet. | [COM-goldens](common.md#com-goldens) |

## Copy keys

`env.*`, `deploy.dialog.*`, `rollback.*`, `promote.*`, `db.*`, plus `state.*` and `lock.*` in common.

## Accessibility and platform

| ID | Rule |
|---|---|
| ENV-32 | Dialog title is read first: "Roll back cazafacturas production, dialog". |
| ENV-33 | Band label: "Environment production on caza-vps, release …". |
| ENV-34 | Web and desktop: disabled buttons stay focusable. The reason shows as tooltip and as text below the actions (WCAG 1.4.1, 4.1.2). |
| ENV-35 | Timeline row is one node: "Release 20261005-221844-9c41e07, healthy, deployed by federico, 5 October 22:18 UTC. Actions available." |
| ENV-36 | Phone: targets 48 dp. The primary is pinned above the bottom nav, 16 dp margins. |
| ENV-37 | Phone sheet: buttons stacked full width, confirm above, Cancel below and focused first. Dismissive goes at the bottom here only. |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Should Deploy accept any ref, or only branches with passing CI? | owner | 2026-10-06 |
| 2 | Show the commit diff between current and target before rollback or promote? It needs git access on the console server. | owner | 2026-10-06 |
| 3 | podship never undoes migrations. List migrations newer than the target (`db migrate status`) in the rollback dialog? Proposed: yes, if the library can return them. | owner + podship | 2026-10-06 |
