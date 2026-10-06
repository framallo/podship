# CLI login, access tokens, CI tokens, origins and the environment lock

Status: draft 2026-10-06 (added on request). Decision: `decisions/2026-10-06-cli-through-console.md`. Mockups: `mockups/web-settings.html` states 5–10, `mockups/web-environment.html` states 5 and 9, `mockups/web-operation.html` state 1 (origin), `mockups/web-history.html` states 1 and 3 (origin filter). Copy: `copy/cli-and-tokens.md`.

Reading this as: an admin and safety layer for the owner, desktop, careful, high restraint; tokens are secrets shown once.

## 1. Job stories

- When I work in the terminal, I want my `podship` commands to show up in the console live, so the console stays the one place that knows what is happening.
- When CI deploys staging, I want it to use a token limited to that project and environment, so a leaked CI secret can't touch production.
- When an environment says it's busy, I want to see who holds it, since when and from where, so I can wait, ask, or (as owner) release it if the holder is gone.

## 2. Screens and states

| Screen | States | Frame |
|---|---|---|
| CLI authorize (`/cli/authorize?code=…`) | Code shown in the terminal and on the page must match; scope and expiry pickers; "Authorize CLI" primary; expired code: "This code expired. Run podship login again." | web-settings 10 |
| Access tokens (`/settings/tokens`) | Table: name, scope, role, expires, last used (time and machine), created; "Create a token"; expiring in < 7 days in warn; expired in ink2 with "Expired" | web-settings 5 |
| Create a token | Name, scope (project / environment checklist), role (≤ own), expiry; validation | web-settings 6 |
| Token created | Shown once in a read-only field with Copy; `podship login --token` hint; "I saved it" | web-settings 7 |
| CI tokens (`/projects/<p>/settings/ci`) | Per project: name, environments, role, expires, last used (run id); "Create a CI token" with the workflow snippet after creation | web-settings 8 |
| Revoke a token | Tier 1: "CLI commands that use federico-mbp stop working at once." | web-settings 9 |
| Lock held | On the environment: run banner "Deploy running · held by federico from CLI on federico-mbp since 11:02 (4 min)" + "Open operation"; disabled actions show the same reason | web-environment 5 |
| Force release | Owner-only tier 2; shows last event time; only enabled after 5 min without events | web-environment 9 |
| Origin labels | Operation header, running indicator, history column and filter | web-operation 1, web-history 1 and 3 |

## 3. Validation

- Token name: 3–40 characters, unique per person; on blur: "You already have a token named federico-mbp."
- Scope: at least one project or environment; on submit.
- Role: options above the person's own role are disabled with "Your role on production is viewer".
- Expiry: a date within 365 days; on blur.

## 4. Accessibility

The one-time token field is read-only, selectable and labeled "New token, shown once"; Copy announces "Copied". The authorize page reads the code digit by digit in its label.

## 5. Acceptance criteria

- No token value is retrievable after the creation dialog closes; only a hash is stored.
- An operation started by `podship deploy` after `podship login` appears in the console's running indicator within 2 s with origin "CLI · <person> on <machine>".
- A token with scope `shop/staging` gets 403 on any other environment; the CLI prints the console's forbidden message.
- Force release is disabled until 5 min without events and is never shown to non-owners.
- History filters by origin: Console, CLI (via console), CI, CLI over SSH.

## 6. Open questions

- Should production deploys from CI tokens be allowed at all, or only promote? (owner)
- Token expiry maximum 365 days, or shorter for production scopes? (owner)
