# How dangerous actions are confirmed

Status: proposed 2026-10-06. Decided by: designer. Source behavior: the podship CLI (README, "Commands").

## Context

The console can stop production, replace a database and remove a person's access. The owner needs two things that pull in opposite directions: an emergency rollback that takes seconds from a phone, and no way to run an operation on production by brushing a button or pressing Enter.

The CLI already tiers this: destructive commands default to `--env staging`, production must be written out, `--yes` is for CI, and restores, `db wipe` and `destroy` ask you to type the project name. In the console the environment is chosen by navigation, not typed, so the CLI's typed string (the project name alone) would not prove the person knows *which* environment they are on.

## Options

1. **Three tiers that mirror the CLI, with the environment in every confirmation and in the typed string (chosen).**
2. Typed confirmation for everything on production. Safest against accidents, but a rollback at 2 a.m. on a phone keyboard becomes slow and error-prone, which defeats J3.
3. Undo instead of confirmation (act now, offer "Undo" for 10 s). Good for reversible edits, wrong here: a rollback or restore restarts containers within seconds, so "undo" would be a second outage.

## Decision

| Tier | Operations | Confirmation |
|---|---|---|
| 0. Run | Read-only views; `backup now`; `backup drill`; `backup pull`; deploy, restart and rollback on a non-production environment; `domain` and `env` changes on a non-production environment | No dialog. The button says what it does and where ("Deploy main to staging"). The operation view opens and shows the plan as its step list. |
| 1. Confirm | On production: deploy, promote, rollback (code only), restart, `env set/unset`, `secret set/unset/copy`, `domain add/remove`, `backup schedule`; anywhere: `access add`, `ci setup`, `server bootstrap` | A dialog (a bottom sheet on compact) that names the environment in its title, states the consequence in one sentence ("The app is down for a few seconds while containers restart"), shows the plan's step titles, and has a confirm button whose label carries the verb, the environment and the target ("Roll back production to 20261005-221844-9c41e07"). |
| 2. Type to confirm | Anywhere: `backup restore`, `rollback --with-db`, `db wipe`, `destroy`, `access remove`, deleting backups | Tier 1 plus a field: "Type **cazafacturas/production** to confirm". The confirm button stays disabled until the text matches exactly (case-sensitive, surrounding spaces trimmed). Paste is allowed: typing is the deliberate act, not a test of memory. |

Rules for every tier-1 and tier-2 confirmation:

- Initial focus is on the dismissive action ("Cancel"), which sits on the left. `Enter` does not confirm; `Esc` cancels. The confirm button activates on pointer-up inside the button (WCAG 2.5.2).
- The title names the environment and the operation: "Roll back production?" is not used (no yes/no questions); the title is "Roll back cazafacturas production".
- The environment band (inverse ink for production) is visible behind the scrim, and the dialog repeats it as a header row.
- No operation on production has a keyboard shortcut that bypasses the dialog. The command palette opens the same dialog.
- A confirmed operation cannot be cancelled (the executor has no cancel). The dialog says so when the operation is long ("This runs to the end even if you close the console").

Emergency path (J3) and accident prevention are the same mechanism:

- When the environment is **healthy**, "Roll back…" is an outlined secondary button in the side panel and an item in each release row's menu.
- When the health check **fails**, the environment page promotes "Roll back to <previous ok release>" to the one filled button, at the top of the page on desktop and pinned above the bottom navigation on the phone; deploy becomes secondary.
- The default target is the newest release with status `ok` that is not current. "Choose another release" opens the list.
- From opening the app on a phone: Overview (production row shows "Unhealthy") → tap the row → tap "Roll back to …" → tap "Roll back production" in the sheet. **4 taps**, no typing. The live view opens on its own.

Locks (a console-server rule; podship itself has none today):

- One operation at a time per environment. While one runs, every mutating action on that environment is disabled with the reason and a link to the running operation ("Deploy running, started 1 min ago by federico").
- A restore also blocks deploys of the same environment, and a deploy blocks a restore.

Permissions: a person without the right on an environment sees the action disabled with the reason ("Only the owner can roll back production"), never hidden (desktop rule: disable, do not hide). The server enforces the same rule (403 → "You don't have permission", never a sign-in loop).

After the fact:

- A rollback ends with "Roll forward to <id>" (rollback `--to` the newer release) as a secondary action.
- A restore ends with the name of the kept database (`cazafacturas_before_20261006T0412`). Swapping back is manual today; a console action for it needs a podship command (open question in `specs/backups.md`).

## Test gate (added 2026-10-06)

Skipping the test stage is a confirmation of its own (`specs/tests.md`): on a non-production environment it is tier 1 with a required reason; on production it is tier 2 (reason plus typed `<project>/<env>`). Production refuses a promote of a release whose tests did not pass unless the same tier-2 override is completed. The reason and the person are stored on the release and in history.

## MCP and provider actions (added 2026-10-06)

Through MCP, tier-1 operations on production need the owner's approval in the console, and tier-2 operations are not exposed at all. Buying a server is tier 1 with the price in the button; destroying a server is tier 2, typed with the server name (`decisions/2026-10-06-providers-first-run-mcp.md`).

## Consequences

The design system needs a `ConfirmDialog` with three tiers and a `TypedConfirmField` (`specs/design-system.md`). The copy tables carry the confirm labels with their variables. The console server must persist the lock and check the role before it calls the library.
