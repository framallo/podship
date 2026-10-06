# Design system: podship_ui

Status: draft 2026-10-06. Brand board: `mockups/brand.html`. Tokens and contrast: `decisions/2026-10-06-visual-direction.md`. CSS mirror for mockups: `mockups/podship.css`.

Purpose: the token set and the component list the Flutter console needs, and where each component comes from.

## Package and rule

- A package `podship_ui` in the console repo: tokens, theme, components. Screens import only `podship_ui`; they never import `naked_ui` or build a `TextStyle` or `Color(` themselves.
- **Component source rule** (`references/flutter-design-system-packages.md`, addendum on Naked UI): the console is a new, desktop-first tool that should not look like stock Material, so interactive controls are built on **naked_ui** primitives (1.1.0, BSD-3-Clause, beta: pin the version) drawn with `podship_ui` tokens. **Material** supplies the app plumbing that is not visual identity (`MaterialApp`, `Theme`/`ThemeExtension`, `Scaffold`, `NavigationRail`/`NavigationBar` shells, `Scrollbar`, `SelectableText`, `Overlay`, localization delegates). Product-specific widgets are **in-house**. Every wrapper ships with semantics, keyboard tests, light/dark goldens and the four `meetsGuideline` checks.
- Icons: Lucide through `lucide_icons_flutter` (3.1.22 on pub.dev, checked 2026-10-06), outlined, 2 px stroke.
- Fonts: IBM Plex Sans (variable) and JetBrains Mono, OFL, bundled as assets.

## Tokens

Tiers: primitives (`_palette.dart`, never imported by screens) → semantic (`PsColors` `ThemeExtension` + `ColorScheme`) → component themes.

| Token | Values |
|---|---|
| `PsColors` (light / dark) | page, surface, container, containerHigh, ink, ink2, outline, hairline, primary, onPrimary, primaryContainer, onPrimaryContainer, inverse, onInverse, ok/okContainer, warn/warnContainer, danger/dangerContainer/onDanger, run/runContainer, logBackground, logInk, logDim, scrim, focusRing (primary; onInverse inside the production band). Hex values and ratios in the visual-direction decision. |
| `PsText` | title 24/32 w600, section 16/24 w600, subsection 14/20 w600, body 14/20 w400, bodyPhone 16/24, label 13/16 w500, caption 12/16 w400, mono 13/20 (JetBrains Mono), monoSmall 12/20, all with `fontVariations` set; tabular figures for numbers |
| `PsSpace` | 4, 8, 12, 16, 24, 32, 48, 64 |
| `PsRadius` | control 6, panel 8, dialog 12, full |
| `PsBreakpoints` | compact < 600, medium 600–839, expanded 840–1199, large ≥ 1200; sidebar 240; side column 340; content max 1152 |
| `PsDensity` | table row 44 (desktop), list row 64 (phone), control height 36 (desktop) / 48 (phone), icon 16 / 20 |
| `PsMotion` | fast 120 ms (hover, press), standard 200 ms (dialogs, sheets), easing standard; `PsMotion.duration(context, …)` returns zero when `MediaQuery.disableAnimationsOf` is true; the running spinner becomes static |
| `PsElevation` | 0 flat (everything on the page), 1 menus and popovers, 2 dialogs and sheets; dark uses tone, not shadow |
| `PsFocus` | 2 px ring, 2 px offset, focusRing color; never removed |
| `PsOpacity` | disabled 0.38 (always with a reason in text) |
| `PsThresholds` | backup age warn 26 h, danger 50 h; drill age warn 30 days; health stale 3 min; disk warn 80 %, danger 90 % |

## Components

| Component | Purpose | Source | States and notes |
|---|---|---|---|
| `PsButton` (filled, outlined, ghost, danger) | Actions | Naked: `NakedButton` | hover, focus, pressed, disabled-with-reason, loading; danger filled only inside confirm dialogs |
| `PsIconButton` | Toolbar actions | Naked: `NakedButton` + `NakedTooltip` | tooltip required by the API |
| `PsTextField`, `PsSecretField` | Inputs | Naked: `NakedTextField` | label above, hint, error (icon + text); secret: obscured, no suggestions, no autofill |
| `PsSelect`, `PsCombobox` | Ref, release, service pickers | Naked: `NakedSelect`, `NakedCombobox` | keyboard type-ahead |
| `PsCheckbox`, `PsRadioGroup`, `PsSwitch` | Options | Naked: `NakedCheckbox`, `NakedRadioGroup`/`NakedRadio`, `NakedToggle` | |
| `PsTabs` | Environment tabs | Naked: `NakedTabs` | arrow keys, routes per tab |
| `PsSegmented` | Theme, time range | Naked: `NakedToggle` group | |
| `PsMenu` | Row menus, account menu | Naked: `NakedMenu` | destructive items last, separated |
| `PsTooltip`, `PsPopover` | Absolute times, reasons | Naked: `NakedTooltip`, `NakedPopover` | never the only place for a reason |
| `PsToast` | "Copied", "Saved" | Naked: `NakedToastController` | no actions inside toasts; never auto-dismiss something with an action |
| `ConfirmDialog` (tiers 1 and 2) and `ConfirmSheet` (compact) | Dangerous actions | Naked: `showNakedDialog` (focus trap, Esc) + in-house layout | header repeats the environment band; initial focus Cancel; Enter does not confirm; pointer-up activation |
| `TypedConfirmField` | Tier-2 typing | in-house on `NakedTextField` | exact match, paste allowed, autocorrect off, enables the confirm button |
| `AppShell` | Sidebar / rail / bottom nav by width | Material `Scaffold`, `NavigationRail`, `NavigationBar`, themed | |
| `CommandPalette` | `Ctrl K` | in-house on `NakedPopover` + `NakedCombobox` | lists every command, disabled ones with reason |
| `EnvironmentBand` | Signature: where you are | in-house | production inverse with lock icon; others hairline; label for assistive tech |
| `StatusPill` | ok, warn, danger, run, neutral | in-house | icon + word always; radius full |
| `HealthIndicator` | Health of an environment | in-house | dot + word + age; stale variant "last known" |
| `AgeText` | "8 h ago" | in-house | absolute time in tooltip and semantics; warn/danger by threshold |
| `ReleaseTimeline` | The release manifest | in-house | current, ok, failed, adopted, pending; test badge; row menu |
| `TestBadge` | Test result of a release | in-house (a `StatusPill` variant) | passed, failed, skipped (with reason), not run |
| `StepList` | Operation steps | in-house | pending, running, done, failed, skipped, recovery group; polite live region |
| `TestSuiteList` | Test stage results | in-house | per suite counts, expandable failing tests with output |
| `LogViewer` | Live and static logs | in-house on `ListView.builder` + `SelectableText` + Material `Scrollbar` | follow/pause, search, wrap, copy, download; virtualized |
| `DataTable` | Every table | in-house on `Table`/`ListView` (not Material `DataTable`, which does not virtualize) | sticky header, group rows, row focus, row menu, empty state slot |
| `DefinitionList` | Key/value panels | in-house | |
| `UsageBar` | CPU, memory, disk | in-house | value always in text |
| `Banner` | Page-level state | in-house | ok, warn, danger, run, neutral; icon + text + optional action |
| `CodeText` | Commands, DNS records | in-house on `SelectableText` | copy button with announcement |
| `Skeleton` | Loading with known layout | in-house | no shimmer under reduced motion |
| `EmptyState`, `ErrorState`, `OfflineBanner`, `StaleMarker` | Empty, error, offline, stale | in-house | empty says why and the next action; error says what happened and what to do; offline/stale show the time of the last data and "Retry now" |
| `ForbiddenNotice` | 403 | in-house | "You don't have permission to …. Ask the owner." never a sign-in loop |

## Tests

- Contrast test over every pair in the decision, light and dark.
- Goldens for every component state, light and dark, at 100 % and 200 % text, in `en` and `es`.
- Keyboard tests for dialogs (initial focus Cancel, Esc, Enter does not confirm), menus and tabs.
- `meetsGuideline`: `textContrastGuideline`, `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`.

## Open questions

naked_ui is beta; if a primitive blocks the build, the fallback is the Material widget with `podship_ui` themes, recorded as a decision.
