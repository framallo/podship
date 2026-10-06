# Live operation stream

Status: proposed 2026-10-06. Decided by: designer. Needs: a change to podship's library (below).

## Context

Every operation is a podship `Plan`: a title, ordered steps (`LocalStep`, `RemoteStep`, `UploadStep`, `HealthStep`, `ActionStep`), and recovery steps that run when a guarded step fails (a deploy's automatic rollback). The `Executor` runs the steps in order. Today it reports through `Log` to stdout and stderr, and remote and local steps inherit stdio (`ssh.stream`, `Process.start(… inheritStdio)`). There is no event sink, no sequence numbers and no cancellation.

Serverpod streams close when the WebSocket dies and never reopen on their own; long work must be shown from persisted state (`references/serverpod-ux.md` in the skill, rules 4 and 10).

## Options

1. **Persisted event log, streamed with resume (chosen).** The console server runs the plan, writes every event with a sequence number to Postgres, and serves `Stream<OperationEvent> watch(operationId, afterSeq)`: it yields a snapshot first (the plan, the state of each step, the last 500 log lines), then tails new events. A client that reconnects passes its last `seq` and misses nothing.
2. Stream only, no persistence. Simpler, but a refresh, a phone going to sleep or a second person opening the view loses the log.
3. Polling every 2 s. Works without WebSockets but makes logs choppy and the running step lag; kept as the fallback when the stream cannot open.

## Decision

**Proposal to podship (not existing behavior):** an `OperationListener` (or a `Stream<OperationEvent>`) passed to `Executor`, with these events:

| Event | Fields | UI |
|---|---|---|
| `planned` | title, steps (title, kind, host), recovery steps, guard range | Step list in pending state; header with the plan title |
| `stepStarted` | index, time | Step becomes "running"; progress "Step 5 of 11" |
| `logLine` | step index, stream (`stdout`/`stderr`/`podship`), text, time | Line in the log viewer under that step |
| `stepFinished` | index, ok, duration, message | Step "done" with duration, or "failed" with the message |
| `recoveryStarted` | failed step index | A "Recovery" group appears; the header says "Rolling back automatically" |
| `finished` | outcome (`succeeded`, `failed`, `recovered`), duration, release id | Outcome banner; history row |

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

podship needs the listener before the console can show real step state; until then the console can only show the CLI's raw output. The history spec separates the fields podship records today (`history.log`: time, action, release, from, user) from the ones the console server adds (duration, outcome, log).
