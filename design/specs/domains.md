# Domains

Status: draft 2026-10-06. Mockups: `mockups/web-domains.html` (3 states). Copy: `copy/domains.md`.

Reading this as: a rarely used setup page, desktop, technical, medium restraint; the DNS record is the thing to copy.

## 1. Job story

J6: add a domain for a project and know exactly which DNS record to create.

## 2. Entry and exits

Entry: environment tab "Domains". Exits: operation view (`domain add`, `domain remove`).

## 3. Primary action

"Add a domain".

## 4. Content

- Proxy: "Cloudflare Tunnel cazafacturas-vps" or "Caddy with Let's Encrypt" (from `proxy.kind`), with the config path.
- Table: host, routes (path regex → port name and number, e.g. `^/(api|v1)/` → api 8086; everything else → web 8087), TLS (Cloudflare edge, or Caddy certificate with expiry), DNS (record podship expects and whether public DNS matches: "Points to the tunnel", "Not pointing yet").
- The DNS record to create, as copyable text: Cloudflare `CNAME cazafacturas.mx → 2b4f…cfargotunnel.com (proxied)`; Caddy `A shop.example.com → 203.0.113.24`.

## 5. States

| State | Frame |
|---|---|
| Ideal: 2 domains on production through the tunnel | web 1 |
| Add a domain: host field, routes (default: everything to web), preview of the DNS record and of the plan (backup tunnel config, write ingress, validate, restart cloudflared) | web 2 |
| DNS not pointing yet: warn row "admin.cazafacturas.mx doesn't resolve to the tunnel yet. Create the CNAME below; it can take a few minutes." | web 3 |
| Proxy none: "This environment has no proxy (proxy.kind: none). Set it in podship.yaml." | spec only |

## 6. Validation

Host: a valid hostname, unique in the server registry (podship refuses a second user): "shop.example.com is already used by shop/production on caza-vps." on blur. Path rule: a valid regex; on blur.

## 7. Components

`DataTable`, `CodeText` with copy, `ConfirmDialog` (tier 1 on production), `Banner`.

## 8. Accessibility

Copy buttons labeled "Copy DNS record for admin.cazafacturas.mx"; confirmation of copy as a polite announcement "Copied".

## 9. Acceptance criteria

The DNS record shown matches podship's output for the proxy kind; a host in use elsewhere is rejected before the operation starts.

## 10. Open questions

Removing the last domain of production: tier 1 or tier 2? Proposed tier 2 (it takes the site off the internet). (owner)
