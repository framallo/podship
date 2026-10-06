# MCP access (Claude Code and other agents)

Status: draft 2026-10-06 (added on request). Decision: `decisions/2026-10-06-providers-first-run-mcp.md`. Mockups: `mockups/web-settings.html` states 11–13, `mockups/web-history.html` state 1 (MCP origin). Copy: `copy/mcp.md`.

Reading this as: a settings page for the owner wiring an AI agent to the console; technical, exact, high restraint; the safety rules must be readable before the command.

## 1. Job story

When I work with Claude Code, I want it to read status and logs and run safe operations through the console, so I don't paste logs by hand; and I want production changes to wait for my approval.

## 2. Page (`/settings/mcp`)

1. What it is: one sentence. "Agents like Claude Code can use podship console through MCP, with a token you control."
2. Connect Claude Code: the command, copyable, with the console URL filled in and the token as `<token>` until one is created:
   `claude mcp add --transport http podship https://console.framallo.dev/mcp --header "Authorization: Bearer <token>"`
3. Tools: a table of every tool, what it does, and its rule (Read, Runs directly, Needs your approval on production, Not available).

| Tool | Does | Rule |
|---|---|---|
| `list_environments` | Projects, environments, health, current release | Read |
| `get_environment` | One environment's state, releases, last backup | Read |
| `get_operation` | Steps, outcome and log of an operation | Read |
| `get_logs` | Container logs with service and time range | Read |
| `list_backups` | Backups and drill results | Read |
| `list_variables` | Variable values and secret keys (never secret values) | Read |
| `deploy` | Deploy a ref | Runs directly on non-production; needs approval on production |
| `promote` | Promote a release | Needs approval (target is production) |
| `rollback` | Roll back, code only | Runs directly on non-production; needs approval on production |
| `restart` | Restart an environment | Runs directly on non-production; needs approval on production |
| `backup_now` | Take a backup | Runs directly |
| `run_restore_drill` | Drill a backup | Runs directly |
| — | Restore, rollback with database, db wipe, destroy, secrets, access, servers, force release | Not available through MCP |

4. MCP tokens: table (name, client last seen, scope, role, expires, last used) and "Create an MCP token" (state 12): name, scope, role (deployer or viewer only; owner is not offered), tools checklist (defaults: all read tools + tier-0 tools), "Production changes need my approval" (always on, shown disabled with the reason).
5. Approvals (state 13): when an agent asks, the console shows a banner on every page and a notification: "Claude Code asks to roll back cazafacturas production to 20261005-221844-9c41e07. Reason it gave: health check failing since 10:51." Actions: "Deny" (left), "Review and approve" (opens the normal tier-1 dialog with origin MCP). Expires after 10 min.

## 3. Origin

Operations from MCP show "MCP · Claude Code · federico (token claude-mbp)" in the operation header, running indicator and history; history filters by origin MCP.

## 4. Acceptance criteria

- No MCP tool can run a tier-2 operation or return a secret value.
- A tier-1 production request through MCP never starts without a person confirming the normal dialog.
- The command on the page has the console's real URL.

## 5. Open questions

- Should approvals also be possible from the phone's lock-screen notification (push)? Proposed: the phone opens the approval page; no one-tap approve. (owner)
