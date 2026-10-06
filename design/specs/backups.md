# Backups (schedule, list, drill, restore, off-site)

Status: draft 2026-10-06. Mockups: `mockups/web-backups.html` (6 states), `mockups/status-phone.html` frame 3. Copy: `copy/backups.md`.

Reading this as: a trust page the owner checks weekly and acts on rarely, under stress when restoring; calm, exact, high restraint.

## 1. Job stories

J1 (backed up?), J4 (drill), J5 (safe restore). HMW make "restore" both provably safe and impossible to start by accident?

## 2. Entry points and exits

Entry: the environment's Backups tab; overview "Last backup" cell; "Needs attention" items. Exits: an operation view (backup now, drill, restore); the server page (schedule slot).

## 3. Primary action

"Run a restore drill" (proves the backups work; the job most often skipped). Secondary: "Back up now", "Restore…" (outlined, in the row menu and the page header's overflow), "Pull to this Mac" when off-site is configured.

## 4. Content

- Summary panel: schedule ("Daily at 03:00 America/Mexico_City, systemd timer podship-backup-cazafacturas"), retention ("Today and yesterday, then 14 daily, 8 weekly, 6 monthly"), encryption ("Encrypted to 2 SSH keys: federico@mbp, federico@backup-yubikey"), off-site ("Pulled to ~/Backups/cazafacturas on federico-mbp, newest pulled 08:12, decrypts and checksums match"), last drill ("21 Sep 2026: 41 tables match, 2 volatile tables differ as expected").
- Backups table: stamp (mono), age, size, contents (database, `uploads` volume, counts, checksums), encrypted copy yes/no, off-site yes/no, origin ("scheduled", "before deploy 20261006-170512-a0dc2b0", "manual"), row menu: "Run a drill on this backup", "Restore…", "Copy stamp".

## 5. States

| State | Frame |
|---|---|
| Ideal list | web 1, phone 3 |
| Drill finished: per-table comparison (tables, rows at backup, rows restored, live now, result), verdict "Backup 2026-10-06T0300 restores. 41 of 41 tables match; 2 volatile tables differ (sessions, job_queue)." | web 2 |
| Restore, step 1: choose a backup (radio list, default newest), shows what happens, in order: fresh backup, stop app services, rename database to `cazafacturas_before_<time>`, restore, start, wait for health | web 3 |
| Restore, step 2: tier-2 dialog, typed `cazafacturas/production`, consequence "The app is down while the restore runs, about 4 min for a 48 MB database." | web 4 |
| Restore finished: ok banner + "The previous database is kept as cazafacturas_before_20261006T1412." + how to switch back | web 5 |
| No schedule (new environment): empty state "No backups yet. Schedule a daily backup or take one now." primary "Schedule daily backups", secondary "Back up now" | web 6 |
| Schedule missed: warn row "Last backup 31 h ago. The 03:00 backup didn't run on 6 Oct." with "Open server" (timer state) | overview web 2 |
| Backup failed (phone): danger line "Backup of 6 Oct failed: disk full on caza-vps (98 %)" | status-phone alt "backup failed" |
| Drill failed: danger verdict naming the tables that differ beyond volatile ones | spec only (same table as web 2 with failed rows) |
| Loading, offline, forbidden | shared patterns |

## 6. Layout

Expanded: summary panel (two-column definition list) above the table; drill result replaces the summary area until dismissed. Compact: summary as a list, backups as rows (stamp, age, size); drill and restore read-only on the phone except "Run a drill" (restore from a phone is allowed only on desktop widths: proposed, see open questions).

## 7. Components

`DefinitionList`, `DataTable`, `StatusPill`, `ConfirmDialog` tier 0/2, `TypedConfirmField`, `RadioList`, `Banner`, `EmptyState`, `CodeText`.

## 8. Validation and behavior

- Typed confirmation: exact match of `<project>/<env>`; the error after a wrong attempt on submit is not needed because the button stays disabled; the hint under the field says what to type.
- A restore is tier 2 on every environment, including staging (the CLI asks for the project name everywhere).
- Restore from an uploaded dump (`--dump`): an option in step 1, "Upload a .dump file", desktop only.
- Lock: a restore blocks deploys and other restores of the environment.

## 9. Accessibility

Table with column headers; row menus labeled "Actions for backup 2026-10-06T0300"; the drill verdict is a live region; the typed field has a visible label, autocorrect and autocapitalize off.

## 10. Acceptance criteria

- The restore dialog cannot be confirmed until `cazafacturas/production` is typed exactly; paste works.
- The dialog lists the steps in the order `restore.sh` runs them and names the kept database.
- A drill on a backup shows a per-table result and a one-sentence verdict.
- Off-site status shows the newest pulled stamp and whether it decrypts.
- Goldens for the 6 web states; `meetsGuideline` x4.

## 11. Open questions

- "Switch back to the previous database": podship has no command for it (README: "swap the names back"). Proposed: `podship backup restore --undo`, then a tier-2 action here. (podship)
- Allow restore from a phone? Proposed no for production (desktop only), yes for drills. (owner)
- Deleting backups is not a podship command; not designed. (owner)
