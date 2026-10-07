# Spec · MCP access

Status: draft 2026-10-06. Key: MCP. Copy: [copy/mcp.md](../copy/mcp.md). Mockups: `mockups/web-settings.html` states 11–13, `mockups/web-history.html` state 1.
Decision: [providers, first run, MCP](../decisions/2026-10-06-providers-first-run-mcp.md).
Read: settings page where the owner connects an AI agent. Technical, exact, high restraint. Safety rules read before the command.

## Purpose

Claude Code reads status and logs and runs safe operations through the console. Production changes wait for the owner's approval.

## Entry and exit

| Route | Content |
|---|---|
| `/settings/mcp` | Intro (`mcp.intro`), connect command, tools table, MCP tokens, approvals |

## States

| State | What shows | Frame |
|---|---|---|
| Page | Connect command, tools, tokens | web-settings 11 |
| Create an MCP token | Name, scope, role, tools checklist, approval switch | web-settings 12 |
| Approval request | Banner on every page and a notification (`approval.banner`) | web-settings 13 |
| Origin | MCP origin in history | web-history 1 |

## Rules

| ID | Kind | Rule |
|---|---|---|
| MCP-1 | ui | The connect command is copyable: `claude mcp add --transport http podship https://console.framallo.dev/mcp --header "Authorization: Bearer <token>"`. |
| MCP-2 | data | The command has the console's real URL. The token shows as `<token>` until one exists. |
| MCP-3 | ui | The tools table shows each tool, what it does and its rule (`mcp.rule.*`). |
| MCP-4 | ui | Tokens table: name, client last seen, scope, role, expires, last used. |
| MCP-5 | data | Token role: deployer or viewer. Owner is not offered (`mcp.tokens.roleLimit`). |
| MCP-6 | data | Default tools: all read tools and tier-0 tools. |
| MCP-7 | ui | "Production changes need my approval" is always on, disabled, with `mcp.tokens.approvalLocked`. |
| MCP-8 | flow | Approval actions: `approval.deny` (left), `approval.review` (opens the tier-1 dialog with origin MCP). |
| MCP-9 | flow | An approval request expires after 10 min. |
| MCP-10 | flow | A tier-1 production request through MCP never starts until a person confirms the normal dialog. |
| MCP-11 | server | No MCP tool can run a tier-2 operation or return a secret value. |
| MCP-12 | ui | MCP operations show `origin.mcp` in the operation header, running indicator and history. History filters by origin MCP. [COM-origin](common.md#com-origin). |

## Tools

Rule values are `mcp.rule.*`. "Approval on prod" means it runs directly elsewhere.

| ID | Tool | Does | Rule |
|---|---|---|---|
| MCP-13 | `list_environments` | Projects, environments, health, current release | Read |
| MCP-14 | `get_environment` | One environment's state, releases, last backup | Read |
| MCP-15 | `get_operation` | Steps, outcome and log of an operation | Read |
| MCP-16 | `get_logs` | Container logs with service and time range | Read |
| MCP-17 | `list_backups` | Backups and drill results | Read |
| MCP-18 | `list_variables` | Variable values and secret keys, never secret values | Read |
| MCP-19 | `deploy` | Deploy a ref | Approval on prod |
| MCP-20 | `promote` | Promote a release | Approval (target is production) |
| MCP-21 | `rollback` | Roll back, code only | Approval on prod |
| MCP-22 | `restart` | Restart an environment | Approval on prod |
| MCP-23 | `backup_now` | Take a backup | Runs directly |
| MCP-24 | `run_restore_drill` | Drill a backup | Runs directly |
| MCP-25 | none | Restore, rollback with database, db wipe, destroy, secrets, access, servers, force release | Not available (`mcp.notAvailable`) |

## Copy keys

`mcp.*`, `approval.*`, `origin.mcp`.

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Approve from a phone lock-screen notification? Proposed: the notification opens the approval page. No one-tap approve. | owner |
