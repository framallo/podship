# History and audit

Status: draft 2026-10-06. Mockups: `mockups/web-history.html` (3 states). Copy: `copy/history.md`.

Reading this as: an audit list read when explaining what happened, desktop, exact, high density.

## 1. Job story

J7: who ran which operation, when, on which release, how long it took, how it ended.

## 2. Data: what exists and what the console adds

Since commit `d837f54`, podship writes one record per operation on the server: `<podship_home>/history/<project>/<env>/<stamp>-<operation>.json` (operation, project, env, host, ok, duration, release, previous release, error, data without sensitive keys, actor, started_at, ended_at, log path) and the `.log` transcript. The older `<dir>/.podship/history.log` has one line per deploy, rollback or promote (time, action, release, from, user) and covers what ran before the records existed.

| Field | Source |
|---|---|
| Time, operation, release, from, duration, outcome, log | the per-operation record (all operations run through the library, from the console, the CLI or CI) |
| By | the record's `actor`; the console passes the signed-in person, the CLI the local user, CI its token name |
| Origin | the console: "Console · person", "CLI · person on machine" (through `podship login`), "CI · token name", "MCP · client · person", "CLI over SSH · user" (records written by a CLI not logged in to the console), "Scheduled" (backup timers); see `decisions/2026-10-06-cli-through-console.md` |
| Legacy rows | `history.log` lines with no record: duration and outcome shown as "Not recorded" |

## 3. Content

Table: time, operation (verb + project/env), release (mono; "from" for rollbacks), by, source, duration, outcome pill. Filters: project, environment, operation type, person, **origin** (Console, CLI, CI, CLI over SSH), outcome, date range. Operations started from the CLI or CI through the console are live like any other and open the same operation view. Row → operation view (or an inline expansion for CLI rows with the raw `history.log` line).

## 4. States

| State | Frame |
|---|---|
| All operations, last 7 days | web 1 |
| One row expanded (CLI row: the raw line; console row: steps summary and "Open operation") | web 2 |
| Filter with no results: "No failed operations on staging in the last 7 days. Clear filters" | web 3 |

## 5. Components

`DataTable` with filters, `StatusPill`, `FilterBar`, `EmptyState`.

## 6. Accessibility

Filter chips are toggle buttons with state; the result count is a polite live region.

## 7. Acceptance criteria

Every operation with a record appears with person, duration and outcome; legacy `history.log` rows are marked and never show invented durations.

## 8. Open questions

Export (CSV) for audits? (owner)
