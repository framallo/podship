# Spec · Logs

Status: draft 2026-10-06. Key: LOG. Copy: [copy/logs.md](../copy/logs.md). Mockups: `mockups/web-logs.html`.
Read: diagnostic tool used right after something breaks, desktop, dense and technical, low decoration.

## Purpose

The owner finds out what broke (J3) and a collaborator reads staging logs (J9).

## States

| State | What shows | Frame |
|---|---|---|
| Following | All services, last 15 min | web 1 |
| Paused | User scrolled up. "Paused. 38 new lines. Jump to latest". Search matches counted. | web 2 |
| Empty | `logs.empty` | web 3 |
| Container not running | `logs.notRunning` with the last lines | spec only |

## Rules

| ID | Kind | Rule |
|---|---|---|
| LOG-1 | data | Source: container logs (`podship logs`). |
| LOG-2 | ui | Service filter: all, server, postgres, pacewright. |
| LOG-3 | ui | Time range: `logs.range.*` or custom `--since`/`--until`. |
| LOG-4 | ui | Toggles: follow, timestamps, wrap. Search highlights and filters. Download. |
| LOG-5 | ui | Each line: local time (UTC in the tooltip), service, text. |
| LOG-6 | ui | Lines that match `error\|exception\|fatal` get the danger color and an "err" label. |
| LOG-7 | flow | Scrolling up pauses follow. "Jump to latest" resumes it. |
| LOG-8 | server | The console server masks secrets in lines. |
| LOG-9 | layout | Expanded: filter toolbar above a full-height viewer. |
| LOG-10 | layout | Compact: filters in a sheet, viewer full width, wrap forced on. |
| LOG-11 | ui | Components: `LogViewer` (shared with the operation view), `Segmented`, `Select`, `SearchField`. |
| LOG-12 | a11y | Text is selectable. A polite live region counts search results (`logs.matches`). |
| LOG-13 | a11y | Follow is a toggle button with its state in the label. |

## Copy keys

`logs.*`. "Paused. 38 new lines. Jump to latest" has no key yet.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Keep history beyond Docker's log retention? Not proposed. | owner |
