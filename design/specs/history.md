# Spec · History and audit

Status: draft 2026-10-06. Key: HIS. Copy: [copy/history.md](../copy/history.md). Mockups: `mockups/web-history.html` (3 states).
Read: audit list read when explaining what happened, desktop, exact, high density.

## Purpose

The owner sees who ran which operation, when, on which release, how long it took and how it ended (J7).

## States

| State | What shows | Frame |
|---|---|---|
| Default | All operations, last 7 days | web 1 |
| Row expanded | CLI row: the raw line. Console row: steps summary and `lock.open`. | web 2 |
| No results | `history.empty` with `history.filter.clear` | web 3 |

## Rules

| ID | Kind | Rule |
|---|---|---|
| HIS-1 | data | Since commit `d837f54`, podship writes one record per operation: `<podship_home>/history/<project>/<env>/<stamp>-<operation>.json` and a `.log` transcript. |
| HIS-2 | data | Record fields: operation, project, env, host, ok, duration, release, previous release, error, actor, started_at, ended_at, log path. |
| HIS-3 | data | The record's data excludes sensitive keys. |
| HIS-4 | data | The older `<dir>/.podship/history.log` has one line per deploy, rollback or promote: time, action, release, from, user. |
| HIS-5 | data | Time, operation, release, from, duration, outcome and log come from the record. This covers console, CLI and CI runs. |
| HIS-6 | data | "By" is the record's `actor`: the console's signed-in person, the CLI's local user, or the CI token name. |
| HIS-7 | data | Origin is set by the console: `origin.*`. CLI over SSH means a CLI not logged in to the console. [COM-origin](common.md#com-origin). |
| HIS-8 | data | A `history.log` line with no record shows duration and outcome as `history.notRecorded`. It never shows invented durations. |
| HIS-9 | ui | Columns: time, operation (verb + project/env), release (mono, "from" for rollbacks), by, origin, duration, outcome pill. |
| HIS-10 | ui | Filters: project, environment, operation type, person, origin (Console, CLI, CI, CLI over SSH), outcome, date range. |
| HIS-11 | flow | CLI and CI operations through the console are live and open the same operation view. |
| HIS-12 | flow | A row opens the operation view. A CLI row expands inline with its raw `history.log` line. |
| HIS-13 | flow | Every operation with a record shows person, duration and outcome. |
| HIS-14 | ui | Components: `DataTable` with filters, `StatusPill`, `FilterBar`, `EmptyState`. |
| HIS-15 | a11y | Filter chips are toggle buttons with state. The result count is a polite live region (`history.count`). |

Origin labels: [CLI through the console](../decisions/2026-10-06-cli-through-console.md).

## Copy keys

`history.*`, `origin.*`, `lock.open`.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Export (CSV) for audits? | owner |
