# Spec · Design system: podship_ui

Status: draft 2026-10-06. Key: DS. Brand board: `mockups/brand.html`. CSS mirror for mockups: `mockups/podship.css`. Decisions: [visual direction](../decisions/2026-10-06-visual-direction.md) (hex values, contrast), [rationale](../decisions/2026-10-07-spec-design-system-rationale.md).

## Purpose

The tokens and components the Flutter console needs, and where each component comes from.

## Package rules

| ID | Rule | Ref |
|---|---|---|
| DS-1 | Package `podship_ui` in the console repo holds tokens, theme and components. | |
| DS-2 | Screens import only `podship_ui`. They never import `naked_ui` and never build a `TextStyle` or `Color(`. | |
| DS-3 | Interactive controls use naked_ui primitives (1.1.0, BSD-3-Clause, beta: pin the version), drawn with `podship_ui` tokens. | [rationale](../decisions/2026-10-07-spec-design-system-rationale.md), `references/flutter-design-system-packages.md` (Naked UI addendum) |
| DS-4 | Material supplies plumbing only: `MaterialApp`, `Theme`/`ThemeExtension`, `Scaffold`, `NavigationRail`/`NavigationBar` shells, `Scrollbar`, `SelectableText`, `Overlay`, localization delegates. | |
| DS-5 | Product-specific widgets are in-house. | |
| DS-6 | Every wrapper ships with semantics, keyboard tests, light/dark goldens and the four `meetsGuideline` checks. | |
| DS-7 | Icons: Lucide through `lucide_icons_flutter` (3.1.22 on pub.dev, checked 2026-10-06), outlined, 2 px stroke. | |
| DS-8 | Fonts: IBM Plex Sans (variable) and JetBrains Mono, OFL, bundled as assets. | |
| DS-9 | Token tiers: primitives (`_palette.dart`, never imported by screens) → semantic (`PsColors` `ThemeExtension` + `ColorScheme`) → component themes. | |

## Tokens

| Token | Values |
|---|---|
| `PsColors` (light / dark) | page, surface, container, containerHigh, ink, ink2, outline, hairline, primary, onPrimary, primaryContainer, onPrimaryContainer, inverse, onInverse. |
| `PsColors` (status, log) | ok/okContainer, warn/warnContainer, danger/dangerContainer/onDanger, run/runContainer, logBackground, logInk, logDim, scrim. |
| `PsColors` (focus) | focusRing: primary, and onInverse inside the production band. |
| `PsText` | title 24/32 w600, section 16/24 w600, subsection 14/20 w600, body 14/20 w400, bodyPhone 16/24, label 13/16 w500, caption 12/16 w400. |
| `PsText` (mono) | mono 13/20 (JetBrains Mono), monoSmall 12/20. All styles set `fontVariations`. Numbers use tabular figures. |
| `PsSpace` | 4, 8, 12, 16, 24, 32, 48, 64 |
| `PsRadius` | control 6, panel 8, dialog 12, full |
| `PsBreakpoints` | compact < 600, medium 600–839, expanded 840–1199, large ≥ 1200. Sidebar 240, side column 340, content max 1152. |
| `PsDensity` | table row 44 (desktop), list row 64 (phone), control height 36 (desktop) / 48 (phone), icon 16 / 20 |
| `PsMotion` | fast 120 ms (hover, press), standard 200 ms (dialogs, sheets), easing standard. |
| `PsMotion` (reduced) | `PsMotion.duration(context, …)` returns zero when `MediaQuery.disableAnimationsOf` is true. The running spinner becomes static. |
| `PsElevation` | 0 flat (everything on the page), 1 menus and popovers, 2 dialogs and sheets. Dark uses tone, not shadow. |
| `PsFocus` | 2 px ring, 2 px offset, focusRing color. Never removed. |
| `PsOpacity` | disabled 0.38, always with a reason in text |
| `PsThresholds` | backup age warn 26 h, danger 50 h. Drill age warn 30 days. Health stale 3 min. Disk warn 80 %, danger 90 %. |

## Components

Source "Naked" means a `naked_ui` primitive. "In-house" means built in `podship_ui`.

| Component | Purpose | Source | States and notes |
|---|---|---|---|
| `PsButton` (filled, outlined, ghost, danger) | Actions | Naked `NakedButton` | Hover, focus, pressed, disabled-with-reason, loading. Danger filled only inside confirm dialogs. |
| `PsIconButton` | Toolbar actions | Naked `NakedButton` + `NakedTooltip` | The API requires a tooltip. |
| `PsTextField`, `PsSecretField` | Inputs | Naked `NakedTextField` | Label above, hint, error (icon + text). Secret: obscured, no suggestions, no autofill. |
| `PsSelect`, `PsCombobox` | Ref, release, service pickers | Naked `NakedSelect`, `NakedCombobox` | Keyboard type-ahead |
| `PsCheckbox`, `PsRadioGroup`, `PsSwitch` | Options | Naked `NakedCheckbox`, `NakedRadioGroup`/`NakedRadio`, `NakedToggle` | |
| `PsTabs` | Environment tabs | Naked `NakedTabs` | Arrow keys, routes per tab |
| `PsSegmented` | Theme, time range | Naked `NakedToggle` group | |
| `PsMenu` | Row menus, account menu | Naked `NakedMenu` | Destructive items last, separated |
| `PsTooltip`, `PsPopover` | Absolute times, reasons | Naked `NakedTooltip`, `NakedPopover` | Never the only place for a reason |
| `PsToast` | "Copied", "Saved" | Naked `NakedToastController` | No actions inside toasts. Never auto-dismiss something with an action. |
| `ConfirmDialog` (tiers 1 and 2), `ConfirmSheet` (compact) | Dangerous actions | Naked `showNakedDialog` (focus trap, Esc) + in-house layout | Header repeats the environment band. Initial focus Cancel. Enter does not confirm. Pointer-up activation. |
| `TypedConfirmField` | Tier-2 typing | In-house on `NakedTextField` | Exact match, paste allowed, autocorrect off. A match enables the confirm button. |
| `AppShell` | Sidebar, rail or bottom nav by width | Material `Scaffold`, `NavigationRail`, `NavigationBar`, themed | |
| `CommandPalette` | `Ctrl K` | In-house on `NakedPopover` + `NakedCombobox` | Lists every command, disabled ones with reason |
| `EnvironmentBand` | Signature: where you are | In-house | Production: inverse with lock icon. Others: hairline. Label for assistive tech. |
| `StatusPill` | ok, warn, danger, run, neutral | In-house | Icon + word always. Radius full. |
| `HealthIndicator` | Health of an environment | In-house | Dot + word + age. Stale variant "last known". |
| `AgeText` | "8 h ago" | In-house | Absolute time in tooltip and semantics. Warn/danger by threshold. |
| `ReleaseTimeline` | The release manifest | In-house | Current, ok, failed, adopted, pending. Test badge. Row menu. |
| `TestBadge` | Test result of a release | In-house, a `StatusPill` variant | Passed, failed, skipped (with reason), not run |
| `StepList` | Operation steps | In-house | Pending, running, done, failed, skipped, recovery group. Polite live region. |
| `TestSuiteList` | Test stage results | In-house | Counts per suite, expandable failing tests with output |
| `LogViewer` | Live and static logs | In-house on `ListView.builder` + `SelectableText` + Material `Scrollbar` | Follow/pause, search, wrap, copy, download. Virtualized. |
| `DataTable` | Every table | In-house on `Table`/`ListView`, not Material `DataTable` | Sticky header, group rows, row focus, row menu, empty state slot |
| `DefinitionList` | Key/value panels | In-house | |
| `UsageBar` | CPU, memory, disk | In-house | Value always in text |
| `Banner` | Page-level state | In-house | ok, warn, danger, run, neutral. Icon + text + optional action. |
| `CodeText` | Commands, DNS records | In-house on `SelectableText` | Copy button with announcement |
| `Skeleton` | Loading with known layout | In-house | No shimmer under reduced motion |
| `EmptyState`, `ErrorState`, `OfflineBanner`, `StaleMarker` | Empty, error, offline, stale | In-house | Empty: why and the next action. Error: what happened and what to do. Offline/stale: time of the last data and "Retry now". |
| `StepIndicator` | Wizards: new server, first-run setup | In-house | Accessible name is the text "Step 2 of 4: Remote access". Done steps show icon and word. |
| `ApprovalRequest` | An agent (MCP) asks for a production change | In-house banner + `ConfirmDialog` | On every page until answered or expired. Deny left. "Review and approve" opens the tier-1 dialog with origin MCP. |
| `OneTimeSecretField` | Tokens, CI keys, private keys shown once | In-house on `NakedTextField` (read-only) + `PsButton` copy | Warning in text. Closing asks nothing more. Never re-openable. |
| `StoredSecretField` | Provider and Cloudflare tokens after saving | In-house | Shows "Saved, ends in …a91f" with Replace and Remove. The value never returns to the client. |
| `ProviderPanel` | Hostinger VPS facts on the server page | In-house on `DefinitionList` | Variant "Added over SSH (no provider)" |
| `OriginLabel` | Console, CLI, CI, MCP, CLI over SSH, Scheduled | In-house, a neutral `StatusPill` | One icon per origin. Full text in semantics. |
| `ForbiddenNotice` | 403 | In-house | "You don't have permission to …. Ask the owner." Never a sign-in loop. |

## Tests

| ID | Rule | Ref |
|---|---|---|
| DS-10 | A contrast test covers every pair in the visual-direction decision, light and dark. | |
| DS-11 | Goldens cover every component state, light and dark, 100 % and 200 % text, `en` and `es`. | [COM-goldens](common.md#com-goldens) |
| DS-12 | Keyboard tests cover dialogs (initial focus Cancel, Esc, Enter does not confirm), menus and tabs. | [COM-dialog](common.md#com-dialog) |
| DS-13 | `meetsGuideline`: `textContrastGuideline`, `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`. | [COM-goldens](common.md#com-goldens) |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | naked_ui is beta. If a primitive blocks the build, the fallback is the Material widget with `podship_ui` themes, recorded as a decision. | not stated | 2026-10-06 |
