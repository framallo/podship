# Environment (releases, deploy, promote, rollback, database)

Status: draft 2026-10-06. Mockups: `mockups/web-environment.html` (8 states), `mockups/rollback-phone.html` frames 2–3 and alternates, `mockups/status-phone.html` frame 2. Copy: `copy/environment.md`.

Reading this as: the page where the owner changes what runs on one environment, at a desk (ship) or on a phone (emergency), exact and careful, highest restraint on production.

## 1. Job stories

J2 (ship to staging, then the same release to production), J3 (roll back now), J9 (collaborator deploys to staging). HMW make a production rollback take four taps and be impossible by accident?

## 2. Entry points and exits

Entry: overview row; sidebar environment; palette ("Deploy cazafacturas to staging"); `/projects/<p>/<env>`. Exits: any operation → `/operations/<id>`; tabs → backups, variables, domains, logs, database; the server name → server page.

## 3. Primary action

Depends on state, so there is always exactly one filled button:

| State | Primary | Secondary |
|---|---|---|
| Healthy, non-production | "Deploy main to staging" | "Restart", "Roll back…" |
| Healthy, production | "Promote from staging" when staging runs a newer release on a compatible server; otherwise "Deploy main to production" | the other one, "Restart", "Roll back…" |
| Unhealthy (health check failing) | "Roll back to <previous ok release>" | "Deploy…", "Restart", "Open logs" |
| Operation running | none (all mutating actions disabled with the reason) | "Open operation" |
| No permission | none | actions disabled with "Only the owner can … production" |

## 4. States

| State | Frame |
|---|---|
| Production, healthy, releases tab | web 1 |
| Deploy to production: tier-1 dialog with ref, commit, plan steps, consequence | web 2 |
| Roll back production: tier-1 dialog, target preselected, "Choose another release", database note | web 3 |
| Production unhealthy: danger banner "Health check failing for 12 min (http://127.0.0.1:8087/health: connection refused)"; rollback is primary | web 4; rollback-phone 2 |
| Operation running on this environment: run banner with step and link; actions disabled with reason | web 5 |
| Staging on agentes.local: promote to production blocked ("agentes.local is arm64 and caza-vps is x86_64. Deploy commit a0dc2b0 to production instead.") with that deploy as the alternative action | web 6 |
| Database tab: engine, size, mode (per environment / shared), migration status (applied vs newest in the release), how to connect (`podship db connect --env production` and `podship tunnel`), database users | web 7 |
| Collaborator view of production: read only, reasons shown | web 8; rollback-phone alt "collaborator" |
| Loading: band and timeline skeletons | spec only (same pattern as overview) |
| Not found: "cazafacturas has no environment named prod. Environments: production, staging." | spec only |
| Server unreachable: band says "Can't reach caza-vps"; last known release shown stale; every action disabled ("Can't reach caza-vps over SSH") | spec only; same banner as server state 4 |
| Phone: status (frame 2 of status flow), rollback confirm sheet, choose another release | phone flows |

## 5. Layout

- Expanded: environment band (signature) under the top bar. Header row: title "cazafacturas / production", health indicator, primary + secondary actions on the trailing side. Tabs: Releases, Backups, Variables, Domains, Logs, Database. Releases tab: two columns. Main: "Current release" panel (id, commit message first line, ref, who, when, duration, images built on, health URLs and their last answer); "Releases" manifest (timeline, newest first, each row: id in mono, status pill, test badge (`specs/tests.md`), deployed by and age, action origin (deploy, promote from staging, rollback, adopt), row menu: "Roll back to this release…", "Copy id", "Open operation"). Side column (340): Health (server URL, public URL, last check), Last backup (age, size, "Back up now"), Staging (its release and "Promote" state), Recent activity (3 rows, link to history).
- Medium: one column; side column becomes a section under the header.
- Compact: band, title, health line, one primary button full width at the bottom above the nav (only when the state has one), tabs as a scrollable bar, the manifest as a list.

## 6. Components and tokens

`EnvironmentBand`, `HealthIndicator`, `StatusPill`, `ReleaseTimeline`, `ConfirmDialog` (tier 1) / `ConfirmSheet` (compact), `TypedConfirmField` (rollback with database), `Banner`, `Tabs`, `DataTable`, `Menu`, `CodeText` (commands with a copy button). Tokens: `inverse`/`onInverse` for the production band; `run` for the running banner; `danger` for unhealthy; the focus ring switches to `onInverse` inside the band.

## 7. Copy

`copy/environment.md`. Behavior strings:

- Confirm labels carry verb, environment and target: "Deploy to production", "Promote 20261006-170512-a0dc2b0 to production", "Roll back production to 20261005-221844-9c41e07".
- Consequence lines: deploy "The app restarts on the new release. If the health check fails, podship switches back on its own."; rollback "The app restarts on the older release, usually in under a minute. The database stays as it is: migrations from newer releases are not undone."

## 8. Validation and behavior

- Deploy dialog: ref field (default `build.ref`, e.g. `main`); the dialog resolves it to a commit before enabling confirm ("main is at a0dc2b0: Fix ticket upload timeout"). Unknown ref: "No branch, tag or commit named mian. Check the name." (on blur). Options: "Skip the pre-deploy backup" (production: off and needs the tier-2 typed string if turned on), "Skip the public URL check".
- Rollback dialog: target radio list (default newest `ok` that is not current; `failed` releases are listed but marked "Failed health check on 4 Oct"); "Also restore the database from a backup" checkbox switches the dialog to tier 2, shows the backup picker (default: the backup taken before the current release's deploy) and the typed field.
- Promote: allowed only when both environments' servers have the same CPU architecture (podship refuses otherwise); disabled with the reason and the deploy alternative. The promote dialog shows the test result of the release being promoted; production refuses a release whose tests did not pass (`specs/tests.md`).
- Deploy runs the test stage first when suites are configured; a failing suite blocks the deploy before anything is built or uploaded.
- Lock: one operation per environment (`decisions/2026-10-06-dangerous-actions.md`).
- After confirm: the operation view opens; on the phone it replaces the sheet.

## 9. Accessibility

- Dialog: focus trapped; initial focus on "Cancel"; Esc cancels; Enter does not confirm; title read first ("Roll back cazafacturas production, dialog").
- The band is a landmark-like header with label "Environment production on caza-vps, release …".
- Disabled buttons keep focusability on web/desktop with their reason as tooltip and as visible text below the actions (WCAG 1.4.1, 4.1.2).
- Timeline rows: one node each, "Release 20261005-221844-9c41e07, healthy, deployed by federico, 5 October 22:18 UTC. Actions available."
- Phone targets 48 dp; the primary button is pinned above the bottom nav with 16 dp margins.
- Phone confirm sheet: the buttons are stacked full width (confirm above, Cancel below, Cancel focused first), the platform pattern for bottom sheets on iOS and Android; this is the one place the "dismissive on the left" rule becomes "dismissive at the bottom".

## 10. Acceptance criteria

- Phone: from the home screen with production unhealthy, a rollback starts in 4 taps (app icon, the production row, "Roll back to …", "Roll back production to …") and no typing; measured on a 390 × 844 build.
- Desktop: with keyboard only, Tab reaches "Roll back to …", Enter opens the dialog with focus on Cancel; pressing Enter again cancels, it never confirms.
- No mutating action on production can be started without a dialog (button, palette, row menu).
- While an operation runs on the environment, every mutating button is disabled and names the running operation.
- Promote between different CPU architectures is disabled with the reason and the alternative.
- Goldens: the 8 web states and the 2 phone frames, light and dark; 200 % text on the compact rollback sheet; `meetsGuideline` x4.

## 11. Open questions

- Should "Deploy" accept any ref, or only branches with passing CI? (owner)
- Should the console show the commit diff between current and target before a rollback or promote? Useful, needs git access on the console server. (owner)
- Migration rollback: podship never undoes migrations; should the rollback dialog list the migrations newer than the target (from `db migrate status`)? Proposed yes, if the library can return them. (owner + podship)
