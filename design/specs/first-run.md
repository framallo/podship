# Spec · First-run setup

Status: draft 2026-10-06. Key: FRN. Copy: [copy/first-run.md](../copy/first-run.md). Mockups: `mockups/web-first-run.html` (7 states).
Decision: [providers, first run, MCP](../decisions/2026-10-06-providers-first-run-mcp.md).
Read: one-time setup for the owner at a desk after install. Plain, one question per step, medium restraint.

## Purpose

After install, the owner becomes owner, reaches the console from the phone and connects a first server.

## Entry and exit

| Way | Detail |
|---|---|
| Entry | The URL the console prints on first start, with a one-time code: `http://localhost:8090/setup?code=K7P-29Q`. |
| No code | `/setup` shows `setup.noCode`. |
| Exit | The overview, or the new-server operation. |

## States

Each step has one primary and a step indicator (`setup.step`).

| State | What shows | Primary | Secondary | Frame |
|---|---|---|---|---|
| 1. Owner | Name, email, sign-in method: passkey (default) or email codes | `setup.owner.confirm` | none | 1 |
| 2. Remote access | Cloudflare API token, zone, hostname (`console.framallo.dev`) | `setup.remote.confirm` | `setup.remote.skip` | 2, error 3 |
| 3. Providers | Hostinger API token (optional) with `setup.providers.test` | `setup.providers.confirm` | `setup.skip` | 4 |
| 4. First server | `setup.server.existing` or `setup.server.create` | `setup.server.confirm` | `setup.server.later` | 5 |
| Done | What was set up and what was skipped, with links to Settings | `setup.done.open` | none | 6 |
| Code expired or used | `setup.used` | "Sign in" | none | 7 |

## Rules

| ID | Kind | Rule |
|---|---|---|
| FRN-1 | flow | Email codes need a mail sender. With none configured, the option is disabled with the reason. |
| FRN-2 | ui | The Cloudflare token hint lists its permissions: Cloudflare Tunnel edit, DNS edit, on one zone. |
| FRN-3 | server | The console creates the tunnel and the DNS record. |
| FRN-4 | flow | Remote access can be set later. Skipping it leaves `setup.localOnly` on the overview. |
| FRN-5 | server | "Test" checks the Hostinger token by listing data centers. |
| FRN-6 | server | Provider tokens are stored on this computer, encrypted. They are never shown again. |
| FRN-7 | flow | An existing server: SSH alias from `~/.ssh/config`, or host, user and key. Then `podship doctor` checks run. |
| FRN-8 | flow | "Create a VPS on Hostinger" opens the new-server flow. |
| FRN-9 | validation | Email on blur. Name required on submit. |
| FRN-10 | validation | The Cloudflare token is checked on `setup.remote.confirm`. Errors name the missing permission (`setup.remote.errPerm`). |
| FRN-11 | validation | Hostname must be inside the chosen zone. On blur. |
| FRN-12 | validation | Hostinger "Test" shows `setup.providers.ok` or `setup.providers.err`. |
| FRN-13 | validation | `podship doctor` results show inline per check: ssh, Docker, compose, disk, ports. |
| FRN-14 | server | Setup does not open without the printed code. The code works once and expires after 24 h. |
| FRN-15 | server | Provider and Cloudflare tokens never return to the browser after saving. Only the last 4 characters do. |
| FRN-16 | a11y | The step indicator is text ("Step 2 of 4: Remote access") and a heading. |
| FRN-17 | a11y | Secrets are password fields with no autofill. |
| FRN-18 | a11y | Errors are icon plus text below the field, summarized at the top on submit. |

## Copy keys

`setup.*`. "Sign in" (code used) has no key yet.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Owner sign-in: passkey or email code? Email code needs SES or SMTP locally. Proposed: passkey first, email code optional. | owner |
| 2 | Import projects from local `podship.yaml` files during setup? | owner |
