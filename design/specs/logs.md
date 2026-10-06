# Logs

Status: draft 2026-10-06. Mockups: `mockups/web-logs.html` (3 states). Copy: `copy/logs.md`.

Reading this as: a diagnostic tool used right after something breaks, desktop, dense and technical, low decoration.

## 1. Job stories

J3 (find out what broke), J9 (collaborator reads staging logs).

## 2. Content and controls

Container logs (`podship logs`): service filter (all, server, postgres, pacewright), time range ("Last 15 min", "Last hour", "Since the current release", custom `--since`/`--until`), follow on/off, timestamps on/off, search (highlights and filters), wrap, download. Each line: time (local, with UTC in the tooltip), service, text. Lines matching `error|exception|fatal` get the danger color and an "err" label.

## 3. States

| State | Frame |
|---|---|
| Following, all services, last 15 min | web 1 |
| Paused (user scrolled up) with "Paused. 38 new lines. Jump to latest"; search "timeout" with 4 matches; service filter server | web 2 |
| No lines in range: "No log lines from server between 10:00 and 10:15. Widen the range or pick another service." | web 3 |
| Container not running: "server isn't running on caza-vps. The last lines before it stopped are below." | spec only |

## 4. Layout

Expanded: toolbar (filters) above a full-height viewer. Compact: filters in a sheet; the viewer full width; line wrap forced on.

## 5. Components

`LogViewer` (shared with the operation view), `Segmented`, `Select`, `SearchField`.

## 6. Accessibility

Selectable text; search results counted in a polite live region ("4 matches"); following state is a toggle button with its state in the label.

## 7. Acceptance criteria

Follow pauses on scroll-up and resumes with "Jump to latest"; secrets are masked in lines (console server rule).

## 8. Open questions

Keep a history beyond Docker's own log retention? Not proposed. (owner)
