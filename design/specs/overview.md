# Overview

Status: draft 2026-10-06. Mockups: `mockups/web-overview.html` (desktop), `mockups/status-phone.html` frame 1 and alternates (phone). Copy: `copy/overview.md`.

Reading this as: the console's home for the owner between tasks or first thing in the morning, desk or phone, calm and exact, high restraint. One question: is everything up and backed up?

## 1. Job story

J1 (`research/job-stories.md`): when I open the console, I want to see whether every environment is up and was backed up last night, so I can stop worrying or know where to look. HMW make that readable in one glance, on a phone?

## 2. Entry points and exits

Entry: sign-in lands here; `/overview`; the logo; `G O`. Exits: a row → its environment page; a server name → server page; a running operation → operation view; "Needs attention" items → the exact tab (backups, environment).

## 3. Primary action

None that changes anything. The focal point is the **attention summary** line at the top: "All 4 environments are healthy. Newest backups are 8 h old or less." or "1 environment needs attention". Secondary: "Add a project" (opens the CLI instructions; adding projects is `podship init` + `link` from the repo, open question below).

## 4. States

| State | What shows | Frame |
|---|---|---|
| Loading (first) | Table with skeleton rows (layout known), summary line replaced by "Checking 2 servers…" | phone: `status-phone.html` alt "loading" |
| Ideal | Summary line in ok; one table grouped by server: environment, project, health, current release and age, last backup age, last drill, running operation | web 1, phone 1 |
| Needs attention | Summary in danger or warn; affected rows first inside their group with the reason in words ("Health check failing for 12 min", "Last backup 31 h ago, schedule missed"); a "Needs attention" list above the table with a link per item | web 2, rollback-phone 1 |
| Partial | One server unreachable: its group shows "Can't reach agentes.local over SSH since 09:41" and its rows show the last known values marked stale; the other group is live | web 2 (server group) |
| Stale (console server unreachable) | Banner "Showing data from 10:52. Can't reach the console server. Retrying in 8 s" with "Retry now"; every age keeps counting; health words get "(last known)" | web 3, phone alt "stale" |
| Empty (first run) | "No servers yet. podship console reads the servers and projects you set up with the CLI." + the three commands (`podship init`, `podship launch --env staging`, then "Add server") and one button "Add a server" | web 4 |
| Unauthorized | Session expired → sign-in with the code; return to `/overview` | shared shell |
| Forbidden | A collaborator sees only the environments they have a role on; no 403 page here | web 1 for owner; settings spec |
| Dark | Same layout | web 5, phone alt "dark" |

## 5. Layout per size class

- Expanded: sidebar; content max 1152; summary line + "Needs attention" list (only when non-empty) + one table grouped by server (group row: server name, OS and arch, CPU and disk use as words and numbers, "Open server"). Columns: Environment (env name + project), Health, Release (id in mono + "2 h ago"), Last backup, Last drill, Activity (running op or last op).
- Medium: rail; the table drops "Last drill" and "Activity" into a second line of each row.
- Compact: bottom nav (Overview, Operations, Servers, Settings). Summary card at top, then one list per server; each row is two lines: "cazafacturas · production" and "Healthy · release 2 h ago · backup 8 h ago". Pull to refresh.

## 6. Components and tokens

`AppShell`, `EnvironmentBand` (not on this page), `StatusPill`, `HealthIndicator`, `AgeText` (relative time with absolute tooltip and stale marking), `DataTable` with group rows, `Banner`, `Skeleton`, `EmptyState`. Tokens: surfaces `page`, `surface`, `container` (group rows); status triads; `id` mono style for releases.

Thresholds (console settings, defaults): backup age warn > 26 h, danger > 50 h; drill age warn > 30 days; health stale after 3 min without a check.

## 7. Copy

`copy/overview.md`. Behavior strings: the summary line has four forms (all healthy / n need attention / checking / stale).

## 8. Validation

None (read only).

## 9. Accessibility

- The summary line is a heading and a polite live region; it is the only thing announced when data refreshes.
- Each row is one semantics node: "cazafacturas production on caza-vps. Healthy. Release 20261006-170512-a0dc2b0, deployed 2 hours ago. Last backup 8 hours ago." (`MergeSemantics`).
- Health never by color: dot + word; pill = icon + word.
- Relative times have the absolute time in the label ("8 hours ago, 6 October 2026 03:00").
- Targets: rows 44 px desktop, 64 px phone. Focus ring on rows; Enter opens.
- 200 % text: phone rows wrap to three lines; the desktop table switches to the medium two-line row at 200 %.

## 10. Acceptance criteria

- With 4 environments on 2 servers, the answer to "everything up and backed up?" is in the first line, without scrolling, at 390 × 844 and at 1440 × 900.
- A backup older than 26 h shows warn with the reason in words; older than 50 h shows danger.
- When the console server is unreachable, the page keeps the last data, shows its time, and every value is marked "last known".
- When one server is unreachable, only its group is marked; the other group stays live.
- `meetsGuideline` (text contrast, tap target Android and iOS, labeled tap targets) passes in light and dark; goldens: ideal, attention, stale, empty, dark, compact.

## 11. Open questions

- Can the console add a project, or only read what `podship link` registered? (owner, before build)
- Should the overview include projects whose environments are all on servers the console cannot reach yet (first SSH key not installed)? (owner)
