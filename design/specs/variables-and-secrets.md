# Variables and secrets

Status: draft 2026-10-06. Mockups: `mockups/web-variables.html` (4 states). Copy: `copy/variables-and-secrets.md`.

Reading this as: a settings table the owner edits a few times a month, desktop, exact, high restraint; secrets are write-only.

## 1. Job story

J6: add a secret without logging into the server and without the value ever being shown.

## 2. Entry and exits

Entry: environment tab "Variables"; palette "Set a secret on cazafacturas production". Exits: restart (after a change), operation view.

## 3. Primary action

"Add" (menu: "Add a variable", "Add a secret"). After a change: "Restart to apply" becomes primary (the change takes effect only after `restart`).

## 4. Content and rules

- Two sections from podship: **Variables** (keys in `plain_env`, values may be shown) and **Secrets** (every other key in `.env`, and the keys in `passwords.yaml`). File shown as a caption: `shared/.env`, `cazafacturas_server/config/passwords.yaml`.
- Secrets show the key, the file, "Set" or "Not set", and the time it last changed if known. **The value is never shown, never sent to the client, never logged.** There is no "reveal" control.
- Set a secret: hidden input (no echo; a "show what I typed" toggle shows only the local text before it is sent), or "Generate a random value" (podship `--generate`: 32 bytes), or "Read from a file". Replacing asks nothing more on staging and is tier 1 on production.
- Copy from another environment (`secret copy --from`): pick keys; values move server to server without passing through the browser.
- Template check: keys in `.env.example` missing on the server are listed as "Not set" with "Set".

## 5. States

| State | Frame |
|---|---|
| Ideal: 7 variables with values, 12 secrets "Set", 1 "Not set" (warn) | web 1 |
| Set a secret dialog (production, tier 1) | web 2 |
| Restart needed: run banner "2 changes are saved on caza-vps and apply after a restart." primary "Restart production…" | web 3 |
| Copy from staging dialog with key checklist | web 4 |
| Files missing (`secret init` never ran): empty state with "Create .env and passwords.yaml" (runs `secret init`, tier 1 on production) | spec only |
| Unreachable server, forbidden: shared | spec only |

## 6. Layout

Expanded: two tables stacked (variables, secrets), search over keys. Compact: read-only list; editing secrets on the phone is not offered (proposed; owner to confirm).

## 7. Components

`DataTable`, `ConfirmDialog` tier 1, `SecretField` (obscured, no autofill, no spellcheck, `enableSuggestions: false`), `Banner`, `Checklist`.

## 8. Validation

- Key: `^[A-Z_][A-Z0-9_]*$` for `.env`; for `passwords.yaml` the key path podship accepts; on blur: "Use capital letters, digits and _. Example: STRIPE_API_KEY."
- Value required unless "Generate" is chosen; on submit.
- Duplicate key: "STRIPE_API_KEY already exists. Set a new value instead." with the action.

## 9. Accessibility

The secret field is a password field for assistive tech; "Set"/"Not set" are words, not icons only. The restart banner is a live region.

## 10. Acceptance criteria

- No API response to the client contains a secret value (test on the endpoint).
- After any change, the restart banner appears and names the number of pending changes.
- Copying secrets shows keys only.

## 11. Open questions

- Show the last-changed time and who changed a secret? podship does not record it; the console server can, for changes made through it. (owner)
