# Spec · Common rules

Status: draft 2026-10-07. Key: COM. Copy: [common](../copy/common.md). Decisions: [dangerous actions](../decisions/2026-10-06-dangerous-actions.md).

## Purpose

Rules that apply to every console screen. A spec links the rule ID. A spec states only its difference from it.

## COM-auth

| Rule |
|---|
| Session expired: the shell goes to sign-in with the code. Copy `state.signedOut`. After sign-in, overview returns to `/overview`. |

## COM-forbidden

| Rule |
|---|
| A collaborator sees only the environments they have a role on. Lists show no 403 page. |
| A direct route without permission shows `ForbiddenNotice` with `state.forbidden`. Never a sign-in loop. |

## COM-loading

| Rule |
|---|
| Loading shows skeleton rows when the layout is known. A summary line names what loads (`state.loading`). |

## COM-stale

| Rule |
|---|
| The console server is unreachable: a banner shows `state.stale` with `common.retry`. |
| Every age keeps counting. Health words get `common.lastKnown`. |

## COM-offline

| Rule |
|---|
| The browser is offline: a banner shows `state.offline`. Data stays. Mutating actions are disabled with the reason (COM-disabled-reason). |

## COM-server-unreachable

| Rule |
|---|
| SSH to a server fails: the affected group or band shows `state.serverUnreachable`. |
| Its last known values show as stale (`common.lastKnown`). Other servers stay live. |
| Every action on that server is disabled with the reason. |

## COM-reconnecting

| Rule |
|---|
| A WebSocket drop shows the persistent banner `state.reconnecting` within 5 s, with `common.retry` and the last event time. |
| Steps keep their last state. The stream resumes from the last sequence without duplicate lines. |

## COM-lock

| Rule |
|---|
| One operation runs per environment at a time. |
| While it runs, every mutating button is disabled and names the running operation (`lock.running`, `lock.open`). |

## COM-disabled-reason

| Rule |
|---|
| A disabled button keeps focus on web and desktop. Its reason shows as a tooltip and as visible text below the actions (WCAG 1.4.1, 4.1.2). |
| Disabled opacity is 0.38, always with a reason in text. |

## COM-dialog

| Rule |
|---|
| Focus is trapped. Initial focus is on Cancel (`common.cancel`, always left). |
| Esc cancels. Enter does not confirm. Buttons activate on pointer-up. |
| Keyboard tests cover initial focus, Esc and Enter. |

## COM-typed-confirm

| Rule |
|---|
| Tier 2: the person types the exact target (`<project>/<env>` or the named alias). Paste works. |
| The confirm button stays disabled until the text matches. The hint `confirm.typeHint` says what to type. |

## COM-shown-once

| Rule |
|---|
| A one-time secret shows in a read-only, selectable field with a copy button. |
| The one-time warning is text, not color. The close button reads "I saved it". Closing warns that the value will not show again. |
| After the dialog closes, the value cannot be retrieved. The server stores only a hash. |

## COM-copy

| Rule |
|---|
| A copy button announces `common.copied` as a polite announcement. |

## COM-origin

| Rule |
|---|
| Every operation names its origin with `origin.*`: operation header, running indicator, history column and filter. |

## COM-status-not-color

| Rule |
|---|
| Health and status never rely on color. A dot has a word. A pill has an icon and a word. Counts and usage bars have numbers and words. |

## COM-relative-time

| Rule |
|---|
| A relative time carries the absolute time in its tooltip and semantics label ("8 hours ago, 6 October 2026 03:00"). |

## COM-reduced-motion

| Rule |
|---|
| Under reduced motion (`MediaQuery.disableAnimationsOf`), `PsMotion` returns zero. The running icon does not spin. Skeletons do not shimmer. |
| The word "Running" always shows next to the icon. |

## COM-goldens

| Rule |
|---|
| Goldens cover every state of the spec, light and dark, 100 % and 200 % text, in en and es. |
| The four `meetsGuideline` tests pass on every golden state: `textContrastGuideline`, `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`. |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Source specs differ on golden text scale and locales. This file takes the design-system matrix. Confirm it applies to every screen. | Designer | 2026-10-07 |
