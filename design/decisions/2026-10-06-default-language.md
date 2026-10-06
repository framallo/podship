# Default language: English, with Spanish second

Status: proposed 2026-10-06 (assumption, owner to confirm). Decided by: designer, from the brief.

## Context

podship is an open-source CLI with an English README, English commands and English log output. Its users are Serverpod developers anywhere. The owner's products ship in English and Spanish (`references/i18n.md` in the product-designer skill).

## Options

1. **English default, Spanish second (chosen).** Matches the CLI, the docs and the open-source audience. Log lines, step titles and command names come from podship in English anyway, so an English UI reads as one voice.
2. Spanish default (es-MX), English second. Matches the owner's own language and CazaFacturas, but every step title and log line would still be English, so the screen would mix languages by default.
3. English only. Cheaper, but the owner's collaborators may prefer Spanish, and adding a locale later costs more than starting with two.

## Decision

- ARB template `app_en.arb`; overlay `app_es.arb` written in Mexican Spanish: tú, infinitives on buttons ("Revertir", "Restaurar"), sentence case, no raya in UI strings.
- The locale follows the browser or device, with an override in Settings stored per person on the server, so emails (sign-in code) use the same language.
- **Never translated:** podship, Serverpod, command names (`podship deploy`), environment names (`production`, `staging`, any user-defined name), project and server names, release ids, service names, file paths, log lines and podship's step titles (they come from the library; the UI frames them in the user's language). See `copy/glossary.md`.
- Dates: relative for recency ("12 min ago", "hace 12 min") with the absolute time on hover and in the accessible label; absolute dates in the user's locale and time zone; release ids stay UTC because they are identifiers.
- Spanish runs about 20–30 % longer: every button and table column is tested with the Spanish string at 390 px and at 200 % text scale (one Spanish frame is in `mockups/rollback-phone.html`).

## Consequences

The copy tables put `en` first. A Spanish reviewer checks the `es` column before release.
