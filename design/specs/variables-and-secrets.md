# Spec · Variables and secrets

Status: draft 2026-10-06. Key: VAR. Copy: [copy/variables-and-secrets.md](../copy/variables-and-secrets.md). Mockups: `mockups/web-variables.html` (4 states).
Read: settings table the owner edits a few times a month, desktop, exact, high restraint. Secrets are write-only.

## Purpose

The owner adds a secret without a server login, and the value never shows (J6).

## Entry and exit

| Way | Detail |
|---|---|
| Entry | Environment tab "Variables". Palette: "Set a secret on cazafacturas production". |
| Exit | Restart after a change. Operation view. |

## States

| State | What shows | Frame |
|---|---|---|
| Ideal | Variables with values. Secrets `vars.state.set`, missing ones `vars.state.notSet` in warn. | web 1 |
| Set a secret | Dialog, tier 1 on production | web 2 |
| Restart needed | Run banner `vars.restart.banner` | web 3 |
| Copy from staging | Dialog with a key checklist | web 4 |
| Files missing | `secret init` never ran. Empty state "Create .env and passwords.yaml" runs `secret init`, tier 1 on production. | spec only |
| Unreachable server, forbidden | [COM-server-unreachable](common.md#com-server-unreachable), [COM-forbidden](common.md#com-forbidden) | spec only |

## Rules

| ID | Kind | Rule |
|---|---|---|
| VAR-1 | ui | Primary: `vars.add` (menu: `vars.add.variable`, `vars.add.secret`). After a change, `vars.restart.action` is primary. |
| VAR-2 | flow | A change applies only after `restart`. The restart banner then names the number of pending changes. |
| VAR-3 | data | Variables: keys in `plain_env`, values may show. Secrets: other `.env` keys and `passwords.yaml` keys. |
| VAR-4 | ui | A caption names the files: `shared/.env`, `cazafacturas_server/config/passwords.yaml`. |
| VAR-5 | ui | A secret shows key, file, set or not set, and last change time if known. |
| VAR-6 | server | A secret value is never shown, never sent to the client, never logged. There is no reveal control. |
| VAR-7 | ui | Set a secret: hidden input, `secret.dialog.generate` (podship `--generate`, 32 bytes), or `secret.dialog.file`. |
| VAR-8 | ui | `secret.dialog.show` shows only the local typed text, before it is sent. |
| VAR-9 | flow | Replacing a secret asks nothing more on staging. It is tier 1 on production. |
| VAR-10 | flow | Copy from another environment (`secret copy --from`) shows keys only. Values go server to server. |
| VAR-11 | flow | Keys in `.env.example` missing on the server show as `vars.state.notSet` with "Set". |
| VAR-12 | test | An endpoint test checks that no API response contains a secret value. |
| VAR-13 | layout | Expanded: variables and secrets tables stacked, search over keys. |
| VAR-14 | layout | Compact: read-only list. Editing secrets on the phone is not offered (proposed, owner to confirm). |
| VAR-15 | ui | Components: `DataTable`, `ConfirmDialog` tier 1, `Banner`, `Checklist`, `SecretField` (obscured, no autofill, no spellcheck, `enableSuggestions: false`). |
| VAR-16 | validation | `.env` key: `^[A-Z_][A-Z0-9_]*$`. `passwords.yaml` key: the key path podship accepts. `vars.keyError` on blur. |
| VAR-17 | validation | Value required unless "Generate" is chosen. On submit. |
| VAR-18 | validation | Duplicate key: `vars.dupError` with the action. |
| VAR-19 | a11y | The secret field is a password field for assistive tech. Set and not set are words, not icons. |
| VAR-20 | a11y | The restart banner is a live region. |

## Copy keys

`vars.*`, `secret.dialog.*`, `copy.dialog.*`. The palette command, "Create .env and passwords.yaml" and "Set" (template row) have no key yet.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Show who changed a secret and when? podship does not record it. The console server can, for its own changes. | owner |
