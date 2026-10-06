# Operation (live view)

Status: draft 2026-10-06. Mockups: `mockups/web-operation.html` (5 states), `mockups/rollback-phone.html` frames 4–5 and alternates. Copy: `copy/operation.md`. Model: `decisions/2026-10-06-live-stream-model.md`.

Reading this as: a progress page the owner watches during a deploy or an emergency rollback, then leaves and comes back to; exact and quiet, high restraint, no celebration.

## 1. Job stories

J2, J3, J7. HMW show a long operation so the owner can leave, come back and still trust what they see?

## 2. Entry points and exits

Entry: confirming any operation; the running-operations indicator in the top bar; a history row; `/operations/<id>` (shareable). Exits: back to the environment; "Roll forward to …" after a rollback; "Open logs"; history.

## 3. Primary action

While running: none (there is no cancel; the executor cannot stop a step safely). After it ends: succeeded → none, a quiet "Back to cazafacturas production"; failed and recovered → "Open logs" is secondary and the primary is "Roll back to …" only if the environment is still unhealthy.

## 4. Structure

Header: plan title in words ("Deploy cazafacturas to production"), the release id in mono, who started it, when, elapsed time, outcome pill. Below: the environment band.

Two panes (expanded): left 400 px **step list** (the plan's step titles from podship, verbatim, numbered; a "Recovery" group appears when recovery starts); right **log viewer** for the selected step (the running step by default), with "All steps" toggle, search, wrap toggle, copy, download.

Deploy step titles shown (from `ops/deploy.dart`): Export main (a0dc2b0) · Build Flutter web: app · Build Flutter web: admin · Select files and write release 20261006-170512-a0dc2b0 · Prepare caza-vps:/srv/cazafacturas-serverpod · Upload files · Create release 20261006-170512-a0dc2b0 · Build images on the server · Back up the database before the switch · Switch to 20261006-170512-a0dc2b0 · Health check · Mark 20261006-170512-a0dc2b0 healthy and keep 5 releases. Recovery: Mark … failed · Roll back to 20261005-221844-9c41e07 · Health check of 20261005-221844-9c41e07.

## 5. States

| State | What shows | Frame |
|---|---|---|
| Running | Step n running with elapsed time; done steps with durations; pending steps in ink2; log following; header "Running · step 8 of 12 · 2 min 41 s" | web 1, phone 4 |
| Failed, recovered (automatic rollback) | Failed step in danger with its message ("not healthy: http://127.0.0.1:8087/health"); "Recovery" group with its steps; outcome banner "Deploy failed. podship switched back to 20261005-221844-9c41e07, which is healthy." | web 2 |
| Succeeded | Outcome banner in ok: "Deployed 20261006-170512-a0dc2b0 to production in 3 min 12 s. Health check passed." | web 3, phone 5 |
| Failed, not recovered | Banner danger: "Rollback failed. The health check of 20261005-221844-9c41e07 did not pass. production may be down." + primary "Open logs" and secondary "Roll back to another release…" | phone alt "rollback failed" |
| Reconnecting | Persistent banner run: "Reconnecting… The operation keeps running on the server." "Retry now"; last event time; steps keep their last state | web 4, phone alt "reconnecting" |
| Not found | "This operation doesn't exist or was deleted after 90 days." link to history | spec only |
| Dark | | web 5 |

## 6. Layout

- Expanded: as above; the step list scrolls independently; the log fills the remaining height.
- Medium: steps above, log below (collapsed to the selected step).
- Compact: step list first; tapping a step opens its log full screen; the outcome banner pins to the top when the operation ends.

## 7. Components and tokens

`StepList` (states: pending, running, done, failed, skipped, recovery), `LogViewer` (lines with time, source, text; levels by stream and podship markers), `StatusPill`, `Banner`, `EnvironmentBand`, `ElapsedTime`. Tokens: `run`/`runContainer` for the running step, `ok`, `danger`, mono 12/20 for logs, the log background (`container` light, `#0C0E10` dark).

## 8. Behavior

- Log follows while scrolled to the bottom; scrolling up pauses: "Paused. 214 new lines. Jump to latest" (button).
- Lines longer than the pane wrap by default (toggle).
- Search highlights matches and jumps; `Ctrl F` focuses it.
- Download gives the full log as text with the operation id in the file name.
- The page title (browser tab) shows the state: "Running · Deploy cazafacturas production".

## 9. Accessibility

- The step list is a polite live region; announcements: "Step 8 of 12, Build images on the server, started", "Deploy succeeded", "Deploy failed, rolling back automatically". Log lines are not announced.
- The log is selectable text, reachable by keyboard; each line has its time in the semantics label.
- Running icon does not spin under reduced motion; the word "Running" is always present.
- Colors in the log are never the only cue: stderr lines carry an "err" source label.

## 10. Acceptance criteria

- Closing and reopening the page during a deploy shows the same steps and every log line since the start (from the persisted events).
- A WebSocket drop shows "Reconnecting…" within 5 s and resumes from the last sequence without duplicate lines.
- The outcome banner states the release that is running now, in every outcome.
- No Cancel control exists.
- Goldens for the 5 web states and phone frames 4–5; `meetsGuideline` x4.

## 11. Open questions

- Notify the owner (email or push) when an operation they started fails or recovers? (owner)
- Should a failed operation offer "Run again"? Re-running a deploy is safe; re-running a restore is not. Proposed: deploy only. (owner)
