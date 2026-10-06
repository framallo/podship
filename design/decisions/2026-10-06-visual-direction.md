# Visual direction: "Harbor ledger"

Status: proposed 2026-10-06. Decided by: designer; the owner chooses between A and B on the brand board (`mockups/brand.html`).

## The read

Operator console for one technical owner, checking state and occasionally acting on production: calm, exact, high restraint, dense on desktop. Color carries state; the accent marks the next action and focus, nothing else.

## Catalog runs (ui-ux-pro-max, vendored; suggestions, not tokens)

| Query | Top result | Verdict |
|---|---|---|
| `"devops infrastructure monitoring dashboard" --design-system` | Style "Glassmorphism"; colors dark slate `#0F172A` with run green `#22C55E` accent; Fira Code + Fira Sans | Glass rejected (`visual-taste.md` §9: not offered; costs frames, fails contrast over busy content). Its pattern note is kept: label telemetry as live only when backed by a current source, with update time and stale state. |
| `"devops deployment developer tool" --domain color -n 3` | Developer Tool / IDE: dark `#0F172A`, accent green `#22C55E`, destructive `#EF4444` with black text | Basis for direction B. A green accent collides with the "healthy" status green (accent lock), and `#EF4444` needs black text. |
| `"technical precise calm developer" --domain typography -n 3` | 1. JetBrains Mono + IBM Plex Sans; 2. Fira Code + Fira Sans | Pair 1 chosen, with the roles swapped: Plex Sans for every heading and UI string, JetBrains Mono only for ids, paths, ports and logs. Fira rejected: Fira Code as a heading face makes every title read as code. |
| `"developer tool dashboard" --domain style -n 2` | Data-Dense Dashboard | Density kept for tables (rows 44 px, 12 px captions); its KPI-card rows and charts rejected (no stat row that does not change a decision). |
| `"live data stale timestamp" --domain ux` | No match (results were "bulk actions" and "auto-play video") | Stale-data rules are this file's own, from the live-stream decision. |
| `"destructive action confirmation" --domain ux` | "Confirmation Dialogs: confirm before delete/irreversible actions", severity high | Agrees; the tiers are in `2026-10-06-dangerous-actions.md`. |

Font checks: IBM Plex Sans is OFL, variable `wght 100..700` and `wdth 75..100`, subsets include `latin-ext` (á é í ó ú ñ ü ¿ ¡). JetBrains Mono is OFL. Both are bundled as package assets in Flutter; Google Fonts is used only by the HTML mockups.

## Directions considered

**A. Harbor ledger (proposed).** Light-first with a full dark theme. Cool near-white paper surfaces, hairline dividers instead of shadows, small radii, one petrol-blue accent, status colors only for state. Calm utility crossed with the minimalist editorial row of `visual-taste.md` §9: hairlines and small radii suit dense tables; the M3 tonal system keeps contrast provable.

**B. Night watch (rejected).** The catalog's dark slate with a run-green accent, dark-only. It looks like every terminal-themed dev tool, a green accent cannot share the screen with green "healthy" without breaking the accent lock, and a dark-only console is harder to read in daylight on a phone. Shown on the brand board as the same fragment for comparison.

## Seed and palettes

The seed `#1F5A7A` (petrol) is the designer's choice from the read, not a catalog value: HCT hue 238.7, chroma 33.5. Its hue is far from the three status hues (green 145, amber 75, red 25), so the accent never reads as a state. Generated with `scripts/tonal_palette.dart` (material_color_utilities 0.13) from the CazaFacturas root, plus intermediate tones from `TonalPalette.get`. Neutral: hue 238.7, chroma 4. Neutral variant: chroma 8. Status: chroma 48–70 for the color, chroma 16 for containers (desaturated, so a page of green pills stays calm).

| Role | Light | Dark | Use |
|---|---|---|---|
| page | `#F9F9FC` (N98) | `#111416` (N6) | Window background |
| surface | `#FFFFFF` (N100) | `#191C1E` (N10) | Panels, tables, dialogs |
| container | `#F0F1F3` (N95) | `#1D2022` (N12) | Sidebar, table headers, log viewer (light) |
| containerHigh | `#E7E8EB` (N92) | `#282A2C` (N17) | Skeletons, pressed rows |
| ink | `#191C1E` (N10) | `#E2E2E5` (N90) | Text |
| ink2 | `#41484D` (NV30) | `#C1C7CE` (NV80) | Secondary text, labels |
| outline | `#71787E` (NV50) | `#8B9198` (NV60) | Field and button edges (≥3:1) |
| hairline | `#DDE3EA` (NV90) | `#41484D` (NV30) | Decorative dividers only |
| primary | `#2A6485` (P40) | `#97CDF3` (P80) | Filled button, links, focus ring, selection |
| onPrimary | `#FFFFFF` | `#00344C` (P20) | Text on primary |
| primaryContainer / on | `#C7E7FF` / `#034C6C` | `#034C6C` / `#C7E7FF` | Selected nav item |
| inverse / onInverse | `#2E3133` / `#F0F1F3` | `#E2E2E5` / `#2E3133` | The production band |
| ok / okContainer | `#296B2A` / `#E1F3D9` | `#91D888` / `#1F2E1D` | Healthy, succeeded |
| warn / warnContainer | `#825500` / `#FFEBD4` | `#FFB94E` / `#372710` | Stale, old backup, pending action |
| danger / dangerContainer / onDanger | `#AF2E27` / `#FFE9E6` / `#FFFFFF` | `#FFB4AB` / `#3D2320` / `#690005` | Unhealthy, failed, destructive confirm |
| run / runContainer | `#2A6485` / `#DFF0FF` | `#97CDF3` / `#1A2C38` | Running (the accent hue: running is the next thing to watch) |
| logBackground | `= container` | `#0C0E10` (N4) | Log viewer |

## Contrast (computed with `scripts/contrast.py`'s `ratio`, 2026-10-06)

Light: ink on page 16.30, on surface 17.13, on container 15.15; ink2 on page 8.85, on surface 9.30, on container 8.23, on containerHigh 7.59; outline on surface 4.48, on page 4.26, on container 3.96, on containerHigh 3.65 (min 3); primary on surface 6.44, on page 6.13; onPrimary on primary 6.44; onPrimaryContainer 7.23; onInverse on inverse 11.59; ok / warn / danger on surface 6.50 / 6.46 / 6.48; on their containers 5.58 / 5.57 / 5.57; run on runContainer 5.54; white on danger 6.48; focus ring (primary) on container 5.70, on containerHigh 5.26; log colors on the light log background: ink 15.15, ink2 8.23, ok 5.75, warn 5.72, danger 5.73, run 5.70.

Dark: ink on page 14.31, on surface 13.25, on container 12.67; ink2 on surface 10.05, on containerHigh 8.46; outline on surface 5.38, on container 5.15, on containerHigh 4.53; primary on surface 10.07; onPrimary on primary 7.74; onInverse on inverse 10.13; ok / warn / danger on surface 10.10 / 10.03 / 10.09; on their containers 8.44 / 8.42 / 8.47; run on runContainer 8.45; onDanger on danger 7.72; focus ring on containerHigh 8.47; log colors on `#0C0E10`: ink 14.96, dim 8.42, danger 11.39, warn 11.33, ok 11.40.

Inside the production band the focus ring switches to onInverse (11.59 light, 10.13 dark), because primary on inverse is only 2.03 (light) and 1.32 (dark).

Disabled controls use 38 % opacity (2.35:1 light, 3.02:1 dark). WCAG 1.4.3 exempts inactive controls; every disabled action in this console also shows its reason as text in ink2, so the state never depends on the faded color.

## The five locks

| Lock | Rule |
|---|---|
| Accent | `primary` only: the one filled button, links, focus, the selected nav item, the current release node. Status colors only for state. No second accent. |
| Shape | Controls 6, panels 8, dialogs and sheets 12, full only for status pills and health dots. No radius on tables or the environment band. |
| Theme | Light and dark both designed. The log viewer is tonal in light (`container`, not an inverted black pane), so no section inverts mid-screen; the production band uses `inverse` on purpose, as a state of the whole page, not a section. |
| Type | IBM Plex Sans: title 24/32 600, section 16/24 600, body 14/20 400 (phone 16/24), label 13/16 500, caption 12/16. JetBrains Mono 13/20 and 12/20 for ids, hosts, ports, paths and logs. Tabular figures for sizes, durations and ages. Phone: three sizes plus mono. |
| Icon | Lucide (ISC), 2 px stroke, 16 px in tables and pills, 20 px in navigation; always outlined; the selected state is shown by the container, not by a filled icon. |

## Signature

The **environment band**: a full-width strip under the top bar naming the environment, its server and its current release. Production is inverse ink with a lock icon; staging is a hairline strip. It is the second-heaviest element on every environment page after the primary action, and it is what the confirm dialogs repeat. The **release manifest** (the timeline of release ids in mono with the current one marked) is the second product-specific element.

## Consequences

New tokens live in the console's UI package (`specs/design-system.md`); a contrast test gates every pair above in both themes.
