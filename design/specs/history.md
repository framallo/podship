# History and audit

Status: draft 2026-10-06. Mockups: `mockups/web-history.html` (3 states). Copy: `copy/history.md`.

Reading this as: an audit list read when explaining what happened, desktop, exact, high density.

## 1. Job story

J7: who ran which operation, when, on which release, how long it took, how it ended.

## 2. Data: what exists and what the console adds

| Field | Source today | Note |
|---|---|---|
| Time | podship `history.log` (UTC) | per environment, on the server |
| Action | `history.log`: deploy, rollback, promote, auto-rollback, adopt | other operations (backup, restore, secret, domain, access) are **not** in `history.log` |
| Release, from | `history.log` | |
| By | `history.log`: the server user (`$SUDO_USER` or `$USER`) | the console adds the person signed in, and `ci:<key name>` for CI |
| Duration, outcome, steps, log | **not recorded by podship** | the console server records them from the event stream, for operations it runs |
| Origin | console | "Console · person", "CLI · person on machine" (through `podship login`), "CI · token name", "CLI over SSH · user" (rows read from `history.log` without a console record); see `decisions/2026-10-06-cli-through-console.md` |

Rows from `history.log` that the console did not run show duration and outcome as "Not recorded (run from the CLI)".

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

Every console-run operation appears with person, duration and outcome; CLI rows are marked as such and never show invented durations.

## 8. Open questions

Export (CSV) for audits? (owner)
