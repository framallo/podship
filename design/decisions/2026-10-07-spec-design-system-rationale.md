# Spec rationale: Design system (podship_ui)

Status: recorded 2026-10-07. Decided by: designer (moved from `specs/design-system.md` on 2026-10-07, no change in meaning).

| Rule | Decision | Why | Options rejected |
|---|---|---|---|
| DS-3 | Interactive controls use naked_ui primitives drawn with `podship_ui` tokens. Material supplies only the plumbing. | The console is a new, desktop-first tool that should not look like stock Material (`references/flutter-design-system-packages.md`, Naked UI addendum). | Stock Material controls. |
| `DataTable` | Every table is in-house on `Table`/`ListView`. | Material `DataTable` does not virtualize. | Material `DataTable`. |
