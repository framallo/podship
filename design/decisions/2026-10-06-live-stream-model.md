# Live operation stream

Status: proposed 2026-10-06. Decided by: designer. Needs: a change to podship's library (below).

## Context

Every operation is a podship `Plan`: a title, ordered steps, and recovery steps that run when a guarded step fails (a deploy's automatic rollback). Since commit `d837f54` (6 Oct 2026) podship's library API (`lib/src/api/`) runs each operation as a typed `Stream<PodshipEvent>`: `OperationStarted` (operation, project, env, host, dry run), `PlanReady` (title, step titles, plan text), `StepStarted` (index, total, title, `recovery` flag), `StepFinished` (index, title, duration), `StepFailed` (index, title, error), `LogLine` (text, level `info|detail|ok|warn|error|output`, `stderr`), `OperationFinished` (an `OperationResult`: ok, duration, release, previous release, error, data). Events carry a UTC time and never secret values. Each operation also writes a history record on the server (`<podship_home>/history/<project>/<env>/<stamp>-<operation>.json` and `.log`) with the actor, start and end, duration, outcome, release and log path.

Still missing for a console: sequence numbers, a step index on `LogLine` (lines belong to the step that is running when they arrive), persistence across a console restart, and cancellation (the executor has none; only the `logs` stream can be cancelled).

Serverpod streams close when the WebSocket dies and never reopen on their own; long work must be shown from persisted state (`references/serverpod-ux.md` in the skill, rules 4 and 10).

## Options

1. **Persisted event log, streamed with resume (chosen).** The console server runs the plan, writes every event with a sequence number to Postgres, and serves `Stream<OperationEvent> watch(operationId, afterSeq)`: it yields a snapshot first (the plan, the state of each step, the last 500 log lines), then tails new events. A client that reconnects passes its last `seq` and misses nothing.
2. Stream only, no persistence. Simpler, but a refresh, a phone going to sleep or a second person opening the view loses the log.
3. Polling every 2 s. Works without WebSockets but makes logs choppy and the running step lag; kept as the fallback when the stream cannot open.

## Decision

**Mapping from the library events to the UI:**

| Library event | UI |
|---|---|
| `OperationStarted` | Header (operation, project/env, host) and the running indicator |
| `PlanReady` | Step list in pending state; header with the plan title |
| `StepStarted` (recovery false / true) | Step becomes "running"; "Step 5 of 11". With `recovery: true` a "Recovery" group appears and the header says "Rolling back automatically" |
| `LogLine` | A line in the log viewer under the running step; `stderr` and `level: error` lines get the danger color and the "err" label; `warn` the warn color |
| `StepFinished` | Step "done" with its duration |
| `StepFailed` | Step "failed" with the error |
| `OperationFinished` | Outcome banner (succeeded; failed; recovered when a recovery step ran and the result names the previous release) and the history row |

**What the console server adds:** a sequence number per event, the operation id, persistence in its database (so a reload, a sleeping phone or a second viewer gets everything), the origin (`Console · person`, `CLI · person on machine`, `CI · token`, `MCP · client`), and the actor string it passes to the library so the server-side history record names the person. **Proposal to podship:** a step index on `LogLine`, so a line can never be attributed to the wrong step when steps overlap.

Secrets: podship already never logs secret values; the console server also masks any value of a known secret key if it ever appears in a line, before it stores the line.

Console-server rules:

- Operations run on the server; closing the view never stops one. There is no Cancel button, because the executor cannot stop a step safely half way (a half-switched release). The view says "Runs to the end even if you close this page."
- Events are kept with the operation for 90 days (the history record keeps outcome, duration and release forever).
- Health is polled every 60 s per environment (the `HealthStep` URLs, fetched from the server), stored with its time. Every health and backup value on screen shows its age; after 3 min without a fresh value it is marked stale.

UI rules:

- The log follows the tail while the user is at the bottom; scrolling up pauses following and shows "Paused. 214 new lines. Jump to latest".
- Connection states: live (no indicator), reconnecting (a persistent banner "Reconnecting… The operation keeps running on the server." with retry backoff 1, 2, 4, 8, max 30 s and a "Retry now" button), offline (banner with the time of the last event).
- Screen readers: the step list is the live region (polite) and announces step changes and the outcome only; log lines are not announced.
- Reduced motion: the running icon does not spin; progress is text.

## Consequences

The console can be built on the library stream as it is; the step index on `LogLine` is a small addition. The history spec reads podship's per-operation records for duration, outcome and log, and the older `history.log` lines only for operations from before the records existed.
