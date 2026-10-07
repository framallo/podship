# Spec · Overview

Status: draft 2026-10-06. Key: OVR. Copy: [overview](../copy/overview.md), [common](../copy/common.md). Mockups: `mockups/web-overview.html`, `mockups/status-phone.html` frame 1 and alternates.
Read: the console home, between tasks or first thing in the morning, desk or phone. Calm, exact, high restraint.

## Purpose

The owner sees in one glance, also on a phone, whether every environment is up and backed up (J1).

## Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | Sign-in, `/overview`, the logo, `G O` | |
| Exit | Environment page, server page, operation view | Tap a row, a server name, a running operation |
| Exit | The exact tab (backups, environment) | Tap a "Needs attention" item |

## States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| Loading | Skeleton rows. Summary is `overview.summary.checking`. | First load | phone alt "loading" |
| Ideal | Summary `overview.summary.allOk` in ok. One table grouped by server (OVR-3). | All healthy | web 1, phone 1 |
| Needs attention | Summary in danger or warn. `overview.attention.title` list above the table, one link per item. Affected rows first in their group, reason in words. | A threshold is crossed (OVR-6) | web 2, rollback-phone 1 |
| Partial | The unreachable server's group shows `state.serverUnreachable` and stale rows. Other groups stay live. | One server unreachable ([COM-server-unreachable](common.md#com-server-unreachable)) | web 2 |
| Stale | `state.stale` banner with `common.retry`. Ages keep counting. Health words get `common.lastKnown`. | Console server unreachable ([COM-stale](common.md#com-stale)) | web 3, phone alt "stale" |
| Empty | `overview.empty.*`, the commands `podship init`, `podship launch --env staging`, then "Add server". One button `overview.empty.action`. | No servers | web 4 |
| Unauthorized | Sign-in with the code, then back to `/overview` | Session expired ([COM-auth](common.md#com-auth)) | shared shell |
| Forbidden | No 403 page. A collaborator sees only environments where they have a role. | Collaborator ([COM-forbidden](common.md#com-forbidden)) | web 1, settings spec |
| Dark | Same layout | Dark theme | web 5, phone alt "dark" |

## Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| OVR-1 | ui | No primary action changes anything. The attention summary line at the top is the focal point. | |
| OVR-2 | ui | Secondary: "Add a project" opens the CLI instructions (`podship init` + `link` from the repo). | Open question 1 |
| OVR-3 | data | Group row: server name, OS and arch, CPU and disk use as words and numbers, `overview.group.open`. | |
| OVR-4 | data | Columns: Environment (env + project), Health, Release (id in mono + age), Last backup, Last drill, Activity (running or last op). | |
| OVR-5 | data | The summary line has four forms: all healthy, n need attention, checking, stale. | |
| OVR-6 | data | Console setting defaults: backup age warn > 26 h, danger > 50 h. Drill age warn > 30 days. Health stale after 3 min without a check. | |
| OVR-7 | layout | Expanded: sidebar, content max 1152. The attention list shows only when not empty. | |
| OVR-8 | layout | Medium: rail. "Last drill" and "Activity" move to a second line of each row. | |
| OVR-9 | layout | Compact: bottom nav (Overview, Operations, Servers, Settings), summary card, one list per server, pull to refresh. | |
| OVR-10 | layout | Compact row, two lines: "cazafacturas · production" and "Healthy · release 2 h ago · backup 8 h ago". | |
| OVR-11 | ui | Components: `AppShell`, `StatusPill`, `HealthIndicator`, `AgeText`, `DataTable` with group rows, `Banner`, `Skeleton`, `EmptyState`. No `EnvironmentBand`. | |
| OVR-12 | ui | Tokens: surfaces `page`, `surface`, `container` (group rows), status triads, `id` mono for releases. | |
| OVR-13 | validation | None. The page is read only. | |
| OVR-14 | test | 4 environments on 2 servers: the answer is the first line, no scrolling, at 390 × 844 and 1440 × 900. | |
| OVR-15 | test | Backup older than 26 h shows warn with the reason in words. Older than 50 h shows danger. | |
| OVR-16 | test | Console server unreachable: the page keeps the last data, shows its time, marks every value "last known". | [COM-stale](common.md#com-stale) |
| OVR-17 | test | One server unreachable: only its group is marked. The other group stays live. | |
| OVR-18 | test | Goldens: ideal, attention, stale, empty, dark, compact. `meetsGuideline` passes in light and dark. | [COM-goldens](common.md#com-goldens) |

## Copy keys

`overview.*` in the copy table, `state.*` and `common.*` in common.

## Accessibility and platform

| ID | Rule |
|---|---|
| OVR-19 | The summary line is a heading and a polite live region. It is the only announcement on refresh. |
| OVR-20 | Each row is one node (`MergeSemantics`): "cazafacturas production on caza-vps. Healthy. Release 20261006-170512-a0dc2b0, deployed 2 hours ago. Last backup 8 hours ago." |
| OVR-21 | Health shows dot + word. Pills show icon + word ([COM-status-not-color](common.md#com-status-not-color)). |
| OVR-22 | Relative times carry the absolute time in the label: "8 hours ago, 6 October 2026 03:00" ([COM-relative-time](common.md#com-relative-time)). |
| OVR-23 | Row targets: 44 px desktop, 64 px phone. Rows show the focus ring. Enter opens. |
| OVR-24 | 200 % text: phone rows wrap to three lines. The desktop table switches to the two-line medium row. |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Can the console add a project, or only read what `podship link` registered? Answer before build. | owner | 2026-10-06 |
| 2 | Include projects whose environments are all on servers the console cannot reach yet (first SSH key not installed)? | owner | 2026-10-06 |
