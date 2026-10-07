# Spec · Domains

Status: draft 2026-10-06. Key: DMN. Copy: [domains](../copy/domains.md). Mockups: `mockups/web-domains.html` (3 states).
Read: a rarely used setup page, desktop, technical, medium restraint. The DNS record is the thing to copy.

## Purpose

The owner adds a domain to a project and knows exactly which DNS record to create (J6).

## Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | Environment tab "Domains" | |
| Exit | Operation view | `domain add`, `domain remove` |

## States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| Ideal | Proxy line, domains table, DNS record (DMN-2 to DMN-4) | 2 domains on production through the tunnel | web 1 |
| Add a domain | Host field, routes (default: everything to web), preview of the DNS record and of the plan | `domains.add` | web 2 |
| DNS not pointing | Warn row `domains.dns.pending` | Public DNS does not match | web 3 |
| No proxy | `domains.noProxy` | `proxy.kind: none` | |

## Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| DMN-1 | ui | Primary: `domains.add`. | |
| DMN-2 | data | Proxy line from `proxy.kind`: `domains.proxy.tunnel` or `domains.proxy.caddy`, with the config path. | |
| DMN-3 | data | Table: host, routes, TLS, DNS. Routes: path regex → port name and number, for example `^/(api|v1)/` → api 8086, else → web 8087. | |
| DMN-4 | data | TLS: Cloudflare edge, or Caddy certificate with expiry. DNS: the expected record and whether public DNS matches. | |
| DMN-5 | data | The record to create is copyable text. Cloudflare: `CNAME cazafacturas.mx → 2b4f…cfargotunnel.com (proxied)`. Caddy: `A shop.example.com → 203.0.113.24`. | [COM-copy](common.md#com-copy) |
| DMN-6 | flow | Add plan steps: back up tunnel config, write ingress, validate, restart cloudflared. | |
| DMN-7 | validation | Host: a valid hostname, unique in the server registry, on blur. In use: `domains.inUse`. | |
| DMN-8 | validation | Path rule: a valid regex, on blur. | |
| DMN-9 | ui | Components: `DataTable`, `CodeText` with copy, `ConfirmDialog` (tier 1 on production), `Banner`. | |
| DMN-10 | test | The DNS record matches podship's output for the proxy kind. | |
| DMN-11 | test | A host in use elsewhere is rejected before the operation starts. podship refuses a second user. | |

## Copy keys

`domains.*` in the copy table.

## Accessibility and platform

| ID | Rule |
|---|---|
| DMN-12 | Copy button label: "Copy DNS record for admin.cazafacturas.mx". Copy confirms with a polite "Copied" ([COM-copy](common.md#com-copy)). |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Removing the last domain of production: tier 1 or tier 2? Proposed: tier 2 (the site goes off the internet). | owner | 2026-10-06 |
