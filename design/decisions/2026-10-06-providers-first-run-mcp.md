# Provisioning servers, first-run setup, and MCP access

Status: proposed 2026-10-06 (added on request during the first round). Decided by: designer; needs console-server work.

## Context

Three additions: the console can create a VPS through a provider (Hostinger first), a fresh console installed on a local computer needs a first-run setup, and AI agents (Claude Code) can drive the console through MCP. All three widen who and what can cause an operation, so they reuse the existing tiers, tokens, origins and lock.

## Provider facts this design depends on (checked 2026-10-06)

From Hostinger's OpenAPI (`https://developers.hostinger.com/openapi/openapi.json`, reference at docs.hostinger.com/api-reference):

- `GET /api/vps/v1/data-centers` returns id, name, country (two letters), city and continent. The console lists what it returns. **Whether a Mexico data center exists was not verified** (it needs an account token); the picker shows Mexico first when the API returns country `mx`, and otherwise says "Hostinger has no data center in Mexico right now" and preselects the nearest by continent.
- `GET /api/billing/v1/catalog` lists plans and prices; `POST /api/vps/v1/virtual-machines` buys one with a catalog `item_id` (example in the spec: `hostingercom-vps-kvm2-usd-1m`) and a `setup` object (`template_id`, `data_center_id`, `hostname`, one `public_key`, `post_install_script_id`, `enable_backups`). More keys go through `POST /api/vps/v1/public-keys/attach/{virtualMachineId}`; firewalls through `/api/vps/v1/firewall…`; progress through `GET /api/vps/v1/virtual-machines/{id}/actions`.
- **There is no endpoint to delete a VPS.** Billing offers `DELETE /api/billing/v1/subscriptions/{id}/auto-renewal/disable`. "Destroy" in the console therefore means: remove podship's environments and registry, stop the VM (`POST …/stop`), turn off auto-renewal, and tell the owner the VPS stays billed until the period ends; deleting it sooner happens in Hostinger's panel. The UI says this before the typed confirmation.

## Decisions

1. **Buying a server is tier 1 with money in the button** ("Buy KVM 2 for US$… per month and set it up"), shows the price from the catalog, the billing period and the payment method, and never runs from MCP.
2. **Provisioning is an operation** with the same live view: Hostinger actions, then `podship server bootstrap` steps, then the Cloudflare tunnel, then registration. Steps: Buy the VPS · Wait for Hostinger to set it up · Attach SSH keys · Create and apply the firewall · Wait for SSH · Install Docker, compose, age and zstd · Apply podship's firewall rules and folders · Create the Cloudflare Tunnel and install cloudflared · Add the SSH alias on the console host · Register the server.
3. **Provider credentials** (Hostinger API token, Cloudflare API token) are stored by the console server encrypted, used server-side only, never returned to any client; the UI shows "Saved, ends in …a91f" (last 4 characters) with "Replace" and "Remove".
4. **First run** is a one-time setup reachable only with the setup code the console prints in its terminal on first start (`http://localhost:8090/setup?code=…`): create the owner, connect a Cloudflare Tunnel and hostname (or stay local), add provider credentials (optional), add the first server (existing over SSH, or create one). Each step can be skipped except the owner; skipping is reversible in Settings.
5. **MCP** endpoint at `<console url>/mcp`, Streamable HTTP, bearer token. MCP tokens are access tokens with type "MCP": scope and role as usual plus a tool list. Rules:
   - Read tools are always available within scope.
   - Tier-0 tools (deploy to non-production, backup now, drill, restart non-production) run directly.
   - Tier-1 tools on production (deploy, promote, rollback, restart) create an **approval request** that the owner approves in the console (or on the phone); the tool returns "Waiting for approval at <url>" and the operation starts only after approval. Requests expire after 10 min.
   - Tier-2 operations (restore, rollback with database, destroy, db wipe, access removal, force release, buying or destroying servers, reading secret values) are **not exposed** through MCP at all.
   - Origin: `MCP · <client name from the MCP handshake> · <person> (token <name>)`, e.g. "MCP · Claude Code · federico (token claude-mbp)".

## Rejected

- Letting MCP run tier-1 operations directly with a "trusted" flag: one prompt injection in a log line could roll back production. Approval keeps a person in the loop at the same cost as clicking the confirm button.
- Exposing restore through MCP with a typed string supplied by the agent: the typed string proves a human read the environment; an agent can copy it.
