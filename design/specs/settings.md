# Settings: people, SSH access, CI keys

Status: draft 2026-10-06. Mockups: `mockups/web-settings.html` (4 states). Copy: `copy/settings.md`.

Reading this as: an admin page used a few times a year, desktop, careful, high restraint.

## 1. Job stories

Owner gives a collaborator limited access (J9), adds or removes a person's SSH key on a server, sets up CI deploys.

## 2. Sections

| Section | Route | Content |
|---|---|---|
| People | `/settings/people` | Who can sign in to the console and their role per environment |
| SSH access | `/settings/access` | Keys in each server's `authorized_keys` marked `podship:<name>` (`podship access list/add/remove`) |
| Access tokens | `/settings/tokens` | Personal access tokens for the CLI (`specs/cli-and-tokens.md`) |
| CI keys and CI tokens | `/settings/ci` (and `/projects/<p>/settings/ci`) | SSH deploy keys from `ci setup`, and CI tokens per project for CI through the console |
| Preferences | `/settings/preferences` | Language, theme (system, light, dark), time zone |

## 3. Roles (console, proposed; granted per project or per environment)

| Role | Can |
|---|---|
| Owner | everything |
| Deployer (per environment) | deploy, restart, roll back code only, back up, drill, read logs and variables (not secrets) on that environment |
| Viewer (per environment) | read status, releases, backups list, logs, history |

Console roles and SSH access are separate: a console role does not give SSH, and an SSH key does not give a console sign-in. The page says so.

## 4. States

| State | Frame |
|---|---|
| People: Federico Ramallo (owner), Ana Lucía Torres (deployer on cazafacturas/staging and shop/staging, viewer on production), Kenji Watanabe (viewer on shop) | web 1 |
| SSH access per server: caza-vps has `federico` (ssh-ed25519, added 2 Oct) and `ci-shop-staging`; agentes.local has `federico`, `ana-lucia` and `ci-cazafacturas-staging` | web 2 |
| CI key created: the private key and the GitHub Actions workflow shown **once**, with "Copy" and "I saved it" (closing warns that it won't be shown again) | web 3 |
| Remove access: tier 2, type the person's name `ana-lucia` | web 4 |
| Access tokens, create, shown once, CI tokens, revoke, CLI authorize | web 5–10 (`specs/cli-and-tokens.md`) |

## 5. Validation

Add SSH key: name `^[a-z0-9-]+$`; key must parse as `ssh-ed25519` or `ssh-rsa`: "This isn't an SSH public key. It starts with ssh-ed25519 or ssh-rsa." on blur. Email for people: on blur.

## 6. Accessibility

The one-time key is in a read-only, selectable field with a copy button; the warning about one-time display is text, not color.

## 7. Acceptance criteria

The private key of a CI deploy key is never retrievable after the dialog closes; removing access is tier 2 and names the servers it affects.

## 8. Open questions

- Where does the console run, and which SSH key does it use? (owner, before build)
- Sign-in method: email code like CazaFacturas, or passkeys? (owner)
