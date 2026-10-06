# The CLI runs through the console (`podship login`)

Status: proposed 2026-10-06 (added on request during the first round). Decided by: designer; needs podship and console-server work.

## Context

The console runs operations with podship's library. If the CLI also talks to the servers over SSH on its own, the console cannot show those operations live, cannot hold a reliable per-environment lock, and history depends on `history.log`, which lacks duration, outcome and person. The request: the CLI can send its commands to the console (`podship login <url>`), with tokens, roles, origins and a visible lock.

## Options

1. **CLI as a client of the console when logged in (chosen).** `podship login https://console.example.com` stores a token; every command then calls the console server, which plans and runs it with the library and streams events back to the terminal. Without login, the CLI keeps working over SSH as today ("CLI over SSH" origin).
2. Console only observes (reads `history.log`, tails logs). No token work, but no live view, no lock, no person.
3. Console required for everything. Simplest model, but a console outage would block an emergency rollback; rejected.

## Decision

- **Login:** `podship login <url>` prints a short code and opens `<url>/cli/authorize`; the signed-in person sees "Authorize the podship CLI on federico-mbp", picks the scope and expiry, and approves. That creates a **personal access token** named after the machine. `podship login --token` accepts a pasted token for headless machines.
- **Personal access tokens:** name, scope (all projects, a project, or project/environment, each with a role no higher than the person's own), expiry (30, 90 or 365 days, or a date; no "never"), created, last used (time and machine), shown **once**, revocable (tier 1: "CLI commands that use it stop working at once").
- **CI tokens:** belong to a **project**, not a person; scope = environments of that project; role deployer or viewer; expiry; shown once with the GitHub Actions snippet (`PODSHIP_URL`, `PODSHIP_TOKEN`). They replace the SSH deploy key when CI goes through the console; `ci setup` over SSH stays for setups without a console.
- **Roles:** owner, deployer, viewer, granted per project or per environment (`specs/settings.md`). A token never exceeds its person's role at the time of use: lowering a person's role lowers their tokens.
- **Origin** of every operation, shown in the operation header, the running indicator and history: `Console · federico`, `CLI · federico on federico-mbp`, `CI · token ci-staging (shop)`, `CLI over SSH · federico` (read from `history.log`, not live).
- **Same live view:** operations started from the CLI appear in the console exactly like console ones; the terminal shows the same events.
- **Lock:** one operation per environment, held by the console server. Visible everywhere an action is disabled: who holds it, which operation, since when, from where. **Force release** is owner-only, tier 2 (typed `<project>/<env>`), and allowed only when the holder shows no events for 5 min (for example a CLI that lost its connection before the server took over); the dialog shows the last event time and warns that a running process on the server could collide with a new operation.
- **Build location:** a deploy through the console exports the commit on the console host. `--worktree` deploys (uncommitted files on a laptop) are not possible through the console; the CLI says so and offers SSH mode.

## Consequences

The console server gets endpoints for the CLI (plan, run, watch), token storage (hashed), role checks per call, and the lock table. History gains an origin filter. `specs/cli-and-tokens.md` holds the screens.
