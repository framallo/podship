# First-run setup (fresh console on a local computer)

Status: draft 2026-10-06 (added on request). Decision: `decisions/2026-10-06-providers-first-run-mcp.md`. Mockups: `mockups/web-first-run.html` (7 states). Copy: `copy/first-run.md`.

Reading this as: a one-time setup for the owner at a desk, right after installing the console; plain, one question per step, medium restraint (a little more space and explanation than the rest of the console).

## 1. Job story

When I install podship console on my computer, I want to make myself the owner, reach it from my phone, and connect my first server, so I can stop using the CLI for everyday checks.

## 2. Entry and exit

Entry: the URL printed by the console on first start, with a one-time setup code (`http://localhost:8090/setup?code=K7P-29Q`). Without the code, `/setup` says "Open the setup link printed in the terminal where the console started." Exit: the overview (or the new-server operation).

## 3. Steps (one primary per step, a step indicator "Step 2 of 4")

| Step | Content | Primary | Secondary | Frame |
|---|---|---|---|---|
| 1. Owner | Name, email; sign-in method: passkey (default) or email codes (needs a mail sender; disabled with the reason when none is configured) | "Create owner and continue" | — | 1 |
| 2. Remote access | Cloudflare Tunnel: Cloudflare API token (permissions listed: Cloudflare Tunnel edit, DNS edit, on one zone), zone, hostname (`console.framallo.dev`); the console creates the tunnel and the DNS record | "Connect and continue" | "Stay on this computer only" (the phone can't reach it; can be set later) | 2, error 3 |
| 3. Providers | Hostinger API token (optional); "Test" checks it by listing data centers; stored on this computer, encrypted, never shown again | "Save and continue" | "Skip" | 4 |
| 4. First server | Two choices: "Add a server I already have" (SSH alias from `~/.ssh/config`, or host, user and key; then `podship doctor` checks run) or "Create a VPS on Hostinger" (opens the new-server flow) | "Add server" | "Do this later" | 5 |
| Done | Summary of what was set up and what was skipped, with links to Settings | "Open the overview" | — | 6 |
| Code expired or used | "This setup link was already used. Sign in instead." | "Sign in" | — | 7 |

## 4. Validation

- Email on blur. Name required on submit.
- Cloudflare token: checked on "Connect and continue"; errors name the missing permission: "This token can't edit DNS for framallo.dev. Create a token with Zone, DNS, Edit on that zone." Hostname must be inside the chosen zone (on blur).
- Hostinger token: "Test" shows "Works. 14 data centers available." or "Hostinger rejected this token (401). Create a new one in hPanel, under API."
- SSH: `podship doctor` results inline per check (ssh, Docker, compose, disk, ports).

## 5. Accessibility

Step indicator is text ("Step 2 of 4: Remote access") and a heading; secrets are password fields with no autofill; errors are icon plus text below the field and summarized at the top on submit.

## 6. Acceptance criteria

- Setup can't be opened without the printed code; the code works once and expires after 24 h.
- Provider and Cloudflare tokens are never sent back to the browser after saving (only the last 4 characters).
- Skipping remote access leaves a reminder on the overview: "The console is only on this computer. Connect a Cloudflare Tunnel to reach it from your phone."

## 7. Open questions

- Passkey or email code as the owner's sign-in (email code needs SES or SMTP on a local install). Proposed: passkey first, email code optional. (owner)
- Should the setup also import projects by reading `podship.yaml` files from local repositories? (owner)
