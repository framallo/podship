# Spec · CLI login, tokens and the environment lock

Status: draft 2026-10-06. Key: CLI. Copy: [copy/cli-and-tokens.md](../copy/cli-and-tokens.md).
Mockups: `mockups/web-settings.html` 5–10, `mockups/web-environment.html` 5 and 9, `mockups/web-operation.html` 1, `mockups/web-history.html` 1 and 3.
Decision: [CLI through the console](../decisions/2026-10-06-cli-through-console.md).
Read: admin and safety layer for the owner, desktop, careful, high restraint. Tokens are secrets shown once.

## Purpose

Terminal and CI commands run through the console, limited by token scope, and the lock shows who holds an environment.

Job stories: CLI commands show live in the console. A CI token limited to one project and environment cannot touch production. A busy environment shows its holder, since when and from where, so the owner can wait, ask or release it.

## States

| State | What shows | Frame |
|---|---|---|
| CLI authorize (`/cli/authorize?code=…`) | Code that must match the terminal, scope and expiry pickers, primary `cli.authorize.confirm` | web-settings 10 |
| Code expired | `cli.authorize.expired` | web-settings 10 |
| Access tokens (`/settings/tokens`) | Table: name, scope, role, expires, last used (time and machine), created. `tokens.create`. | web-settings 5 |
| Create a token | Name, scope (project and environment checklist), role (≤ own), expiry | web-settings 6 |
| Token created | Token once in a read-only field with Copy, `tokens.created.use`, `tokens.created.done` | web-settings 7 |
| CI tokens (`/projects/<p>/settings/ci`) | Per project: name, environments, role, expires, last used (run id). `ci.tokens.create`, then `ci.tokens.snippet`. | web-settings 8 |
| Revoke | Tier 1 with `tokens.revoke.body` | web-settings 9 |
| Lock held | Run banner `lock.held` with `lock.open`. Disabled actions show the same reason. | web-environment 5 |
| Force release | Owner-only tier 2 with the last event time | web-environment 9 |
| Origin labels | Operation header, running indicator, history column and filter | web-operation 1, web-history 1 and 3 |

## Rules

| ID | Kind | Rule |
|---|---|---|
| CLI-1 | ui | A token that expires in under 7 days shows in warn. An expired token shows in ink2 with `tokens.expired`. |
| CLI-2 | validation | Token name: 3–40 characters, unique per person. `tokens.nameError` on blur. |
| CLI-3 | validation | Scope: at least one project or environment. On submit. |
| CLI-4 | validation | Roles above the person's own are disabled with `tokens.dialog.roleLimit`. |
| CLI-5 | validation | Expiry: a date within 365 days. On blur. |
| CLI-6 | server | A token value is never retrievable after the dialog closes. The server stores only a hash. [COM-shown-once](common.md#com-shown-once). |
| CLI-7 | flow | After `podship login`, a `podship deploy` shows in the running indicator within 2 s with `origin.cli`. [COM-origin](common.md#com-origin). |
| CLI-8 | server | A token scoped to `shop/staging` gets 403 on any other environment. The CLI prints the console's forbidden message. |
| CLI-9 | flow | Force release is enabled only after 5 min without events. Non-owners never see it. |
| CLI-10 | ui | History filters by origin: Console, CLI (via console), CI, CLI over SSH. |
| CLI-11 | a11y | The one-time token field is read-only, selectable and labeled "New token, shown once". Copy announces `common.copied`. |
| CLI-12 | a11y | The authorize page reads the code digit by digit in its label. |

## Copy keys

`cli.*`, `tokens.*`, `ci.tokens.*`, `lock.*`, `origin.*`. "New token, shown once" has no key yet.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Allow production deploys from CI tokens, or only promote? | owner |
| 2 | Token expiry maximum 365 days, or shorter for production scopes? | owner |
