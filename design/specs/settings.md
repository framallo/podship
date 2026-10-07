# Spec · Settings

Status: draft 2026-10-06. Key: SET. Copy: [copy/settings.md](../copy/settings.md). Mockups: `mockups/web-settings.html`.
Read: admin page, used a few times a year, desktop, careful, high restraint.

## Purpose

The owner gives collaborators limited access, manages server SSH keys and sets up CI deploys (J9).

## Entry and exit

| Route | Content |
|---|---|
| `/settings/people` | People and their role per environment |
| `/settings/access` | Keys in each server's `authorized_keys` marked `podship:<name>` (`podship access list/add/remove`) |
| `/settings/tokens` | CLI access tokens (web 5–10), see [cli-and-tokens.md](cli-and-tokens.md) |
| `/settings/ci`, `/projects/<p>/settings/ci` | SSH deploy keys from `ci setup`. CI tokens per project. |
| `/settings/preferences` | Language, theme (system, light, dark), time zone |

## States

| State | What shows | Frame |
|---|---|---|
| People | Each person with a role per project or environment | web 1 |
| SSH access | Keys per server: name, type, date added | web 2 |
| CI key created | Private key and GitHub Actions workflow, once, with `common.copy` and `ci.created.done` | web 3 |
| Remove access | Tier 2: type the person's name (`ana-lucia`) | web 4 |

## Rules

| ID | Kind | Rule |
|---|---|---|
| SET-1 | data | Roles (proposed) are per project or environment. Owner: everything. |
| SET-2 | data | Deployer: deploy, restart, roll back code only, back up, drill, read logs and variables. No secrets. |
| SET-3 | data | Viewer: read status, releases, backups list, logs, history. |
| SET-4 | flow | A console role gives no SSH access. An SSH key gives no console sign-in. The page shows `people.separate`. |
| SET-5 | flow | The CI private key is never retrievable after the dialog closes. Closing warns it does not show again. [COM-shown-once](common.md#com-shown-once). |
| SET-6 | flow | Remove access is tier 2 and names the affected servers. |
| SET-7 | validation | Key name: `^[a-z0-9-]+$`. |
| SET-8 | validation | Key must parse as `ssh-ed25519` or `ssh-rsa`, else `access.keyError` on blur. |
| SET-9 | validation | Email: on blur. |
| SET-10 | a11y | The one-time key is a read-only, selectable field with a copy button. |
| SET-11 | a11y | The one-time warning is text, not color. |

## Copy keys

`settings.*`, `people.*`, `access.*`, `ci.created.*`, `prefs.*`.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Where does the console run, and which SSH key does it use? | owner, before build |
| 2 | Sign-in: email code like CazaFacturas, or passkeys? | owner |
