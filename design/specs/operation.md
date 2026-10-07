# Spec · Operation (live view)

Status: draft 2026-10-06. Key: OPS. Copy: [operation](../copy/operation.md), [common](../copy/common.md). Mockups: `mockups/web-operation.html` (5 states), `mockups/rollback-phone.html` frames 4–5 and alternates. Decisions: [live stream model](../decisions/2026-10-06-live-stream-model.md), [rationale](../decisions/2026-10-07-spec-operation-rationale.md).
Read: a progress page the owner watches during a deploy or emergency rollback, leaves, and comes back to. Exact, quiet, high restraint, no celebration.

## Purpose

The owner follows a long operation, leaves, comes back, and can still trust what the page shows (J2, J3, J7).

## Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | Confirming any operation, the top-bar running indicator, a history row, `/operations/<id>` (shareable) | |
| Exit | The environment, `op.failed.next`, history | |
| Exit | "Roll forward to …" (`rollback.done.forward`) | After a rollback |

## States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| Running | Step n running with elapsed time. Done steps with durations. Pending steps in `ink2`. Log follows. Header "Running · step 8 of 12 · 2 min 41 s". | Operation in progress | web 1, phone 4 |
| Failed, recovered | Failed step in danger with its message ("not healthy: http://127.0.0.1:8087/health"). "Recovery" group with its steps. Banner `op.recovered`. | Automatic rollback succeeds | web 2 |
| Succeeded | Ok banner `op.done.deploy`. Quiet `op.back`, no primary. | Health check passes | web 3, phone 5 |
| Failed, not recovered | Danger banner `op.failed.rollback`. Primary `op.failed.next`, secondary `op.failed.other`. | Rollback health check fails | phone alt "rollback failed" |
| Reconnecting | Persistent run banner `state.reconnecting`, `common.retry`, last event time. Steps keep their last state. | WebSocket drops ([COM-reconnecting](common.md#com-reconnecting)) | web 4, phone alt "reconnecting" |
| Not found | `op.notFound` with a link to history | Unknown or deleted id | |
| Dark | Same layout | Dark theme | web 5 |

## Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| OPS-1 | flow | While running there is no primary action and no Cancel control. | [rationale](../decisions/2026-10-07-spec-operation-rationale.md) |
| OPS-2 | flow | Failed and recovered: "Open logs" is secondary. The primary is "Roll back to …" only if the environment is still unhealthy. | |
| OPS-3 | data | Header: plan title in words ("Deploy cazafacturas to production"), release id (mono), who, when, elapsed time, outcome pill. | |
| OPS-4 | layout | The environment band shows below the header. | |
| OPS-5 | data | Step list: podship's plan step titles, verbatim and numbered. A "Recovery" group appears when recovery starts. | |
| OPS-6 | data | Deploy steps (`ops/deploy.dart`): Export main (a0dc2b0) · Build Flutter web: app · Build Flutter web: admin · Select files and write release 20261006-170512-a0dc2b0. | |
| OPS-7 | data | Then: Prepare caza-vps:/srv/cazafacturas-serverpod · Upload files · Create release 20261006-170512-a0dc2b0 · Build images on the server. | |
| OPS-8 | data | Then: Back up the database before the switch · Switch to 20261006-170512-a0dc2b0 · Health check · Mark 20261006-170512-a0dc2b0 healthy and keep 5 releases. | |
| OPS-9 | data | Recovery: Mark … failed · Roll back to 20261005-221844-9c41e07 · Health check of 20261005-221844-9c41e07. | |
| OPS-10 | data | The outcome banner names the release that runs now, in every outcome. | |
| OPS-11 | layout | Expanded: step list left, 400 px, scrolls on its own. Log viewer right, fills the remaining height, shows the selected step. | |
| OPS-12 | layout | The running step is selected by default. Log tools: `op.log.all`, search, `op.log.wrap`, copy, `op.log.download`. | |
| OPS-13 | layout | Medium: steps above, log below, collapsed to the selected step. | |
| OPS-14 | layout | Compact: step list first. A tap on a step opens its log full screen. The outcome banner pins to the top when the operation ends. | |
| OPS-15 | ui | Components: `StepList` (pending, running, done, failed, skipped, recovery), `LogViewer`, `StatusPill`, `Banner`, `EnvironmentBand`, `ElapsedTime`. | |
| OPS-16 | ui | `LogViewer` lines show time, source, text. Levels come from the stream and podship markers. | |
| OPS-17 | ui | Tokens: `run`/`runContainer` running step, `ok`, `danger`, mono 12/20 for logs. Log background: `container` light, `#0C0E10` dark. | |
| OPS-18 | flow | The log follows while scrolled to the bottom. Scrolling up pauses it: `op.log.paused` with the button `op.log.jump`. | |
| OPS-19 | flow | Long lines wrap by default. The wrap toggle turns it off. | |
| OPS-20 | flow | Search highlights matches and jumps to them. `Ctrl F` focuses search. | |
| OPS-21 | flow | Download gives the full log as text. The file name has the operation id. | |
| OPS-22 | flow | The browser tab title shows the state: "Running · Deploy cazafacturas production". | |
| OPS-23 | test | Closing and reopening during a deploy shows the same steps and every log line since the start, from persisted events. | |
| OPS-24 | test | A WebSocket drop shows "Reconnecting…" within 5 s. It resumes from the last sequence with no duplicate lines. | [COM-reconnecting](common.md#com-reconnecting) |
| OPS-25 | test | Goldens: the 5 web states and phone frames 4–5. `meetsGuideline` x4. | [COM-goldens](common.md#com-goldens) |

## Copy keys

`op.*` in the copy table. `state.reconnecting`, `common.retry` in common.

## Accessibility and platform

| ID | Rule |
|---|---|
| OPS-26 | The step list is a polite live region. It announces "Step 8 of 12, Build images on the server, started", "Deploy succeeded", "Deploy failed, rolling back automatically". |
| OPS-27 | Log lines are not announced. The log is selectable text, reachable by keyboard. Each line has its time in the label. |
| OPS-28 | Reduced motion: the running icon does not spin. The word "Running" is always present ([COM-reduced-motion](common.md#com-reduced-motion)). |
| OPS-29 | Color is never the only cue in the log. stderr lines carry an "err" source label. |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Notify the owner (email or push) when an operation they started fails or recovers? | owner | 2026-10-06 |
| 2 | Should a failed operation offer "Run again"? A deploy is safe to run again. A restore is not. Proposed: deploy only. | owner | 2026-10-06 |
