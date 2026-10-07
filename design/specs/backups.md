# Spec · Backups

Status: draft 2026-10-06. Key: BAK. Copy: [copy/backups.md](../copy/backups.md). Mockups: `mockups/web-backups.html` (6 states), `mockups/status-phone.html` frame 3.
Decisions: [dangerous actions](../decisions/2026-10-06-dangerous-actions.md), [rationale](../decisions/2026-10-07-spec-backups-rationale.md).
Read: trust page checked weekly, acted on rarely, under stress when restoring. Calm, exact, high restraint.

## Purpose

The owner knows the backups ran (J1), proves they restore (J4) and restores safely (J5), never by accident.

## Entry and exit

| Way | Detail |
|---|---|
| Entry | Environment Backups tab. Overview "Last backup" cell. "Needs attention" items. |
| Exit | Operation view (backup now, drill, restore). Server page (schedule slot). |

## States

| State | What shows | Frame |
|---|---|---|
| Ideal | Summary panel and backups table | web 1, phone 3 |
| Drill finished | Per-table comparison and verdict `drill.verdict.ok` | web 2 |
| Restore step 1 | Choose a backup (radio list, newest default) and `restore.step1.list` in order | web 3 |
| Restore step 2 | Tier-2 dialog, typed `cazafacturas/production`, `restore.dialog.consequence` | web 4 |
| Restore finished | Ok banner, `restore.done.kept` and how to switch back | web 5 |
| No schedule | `backups.empty.*`. Primary `backups.empty.action`, secondary `backups.action.now`. | web 6 |
| Schedule missed | Warn row "Last backup 31 h ago. The 03:00 backup didn't run on 6 Oct." with "Open server" (timer state) | overview web 2 |
| Backup failed | Phone danger line `backups.failed` | status-phone alt "backup failed" |
| Drill failed | `drill.verdict.fail`, naming tables that differ beyond volatile ones | spec only (web 2 with failed rows) |
| Loading, offline, forbidden | [COM-loading](common.md#com-loading), [COM-offline](common.md#com-offline), [COM-forbidden](common.md#com-forbidden) | |

## Rules

| ID | Kind | Rule |
|---|---|---|
| BAK-1 | ui | Primary: `backups.action.drill`. Secondary: `backups.action.now`, `backups.action.restore`, `backups.action.pull` (off-site only). |
| BAK-2 | ui | "Restore…" is outlined, in the row menu and the header overflow. |
| BAK-3 | ui | Summary: schedule (`backups.schedule`, systemd timer `podship-backup-<project>`), retention, encryption, off-site, last drill. |
| BAK-4 | data | Mockup retention: today and yesterday, then 14 daily, 8 weekly, 6 monthly. Encryption to 2 SSH keys. |
| BAK-5 | ui | Table columns: stamp (mono), age, size, contents, encrypted copy, off-site, origin (`backups.origin.*`). |
| BAK-6 | ui | Contents: database, `uploads` volume, counts, checksums. |
| BAK-7 | ui | Row menu: "Run a drill on this backup", "Restore…", "Copy stamp". |
| BAK-8 | ui | Drill table columns: `drill.col`. A drill shows a per-table result and a one-sentence verdict. Volatile tables (sessions, job_queue) differ as expected. |
| BAK-9 | flow | Restore order, as `restore.sh` runs it: fresh backup, stop app services, rename database to `cazafacturas_before_<time>`, restore, start, wait for health. |
| BAK-10 | flow | The restore dialog lists those steps and names the kept database. |
| BAK-11 | flow | The confirm button stays disabled until `<project>/<env>` matches exactly. Paste works. No error after a wrong attempt. |
| BAK-12 | ui | The hint under the typed field says what to type (`confirm.typeHint`). |
| BAK-13 | flow | A restore is tier 2 on every environment, staging included. |
| BAK-14 | flow | Step 1 offers `restore.step1.upload` (`--dump`), desktop only. |
| BAK-15 | flow | A restore locks the environment against deploys and other restores. |
| BAK-16 | ui | Off-site status shows the newest pulled stamp and whether it decrypts. |
| BAK-17 | layout | Expanded: summary panel (two-column definition list) above the table. A drill result replaces the summary until dismissed. |
| BAK-18 | layout | Compact: summary as a list, backups as rows (stamp, age, size). |
| BAK-19 | platform | Phone: drill and restore are read-only except "Run a drill". Restore only on desktop widths (proposed). |
| BAK-20 | ui | Components: `DefinitionList`, `DataTable`, `StatusPill`, `ConfirmDialog` tier 0/2, `TypedConfirmField`, `RadioList`, `Banner`, `EmptyState`, `CodeText`. |
| BAK-21 | a11y | Table has column headers. Row menus are labeled "Actions for backup 2026-10-06T0300". |
| BAK-22 | a11y | The drill verdict is a live region. |
| BAK-23 | a11y | The typed field has a visible label, autocorrect and autocapitalize off. |
| BAK-24 | test | Goldens for the 6 web states. `meetsGuideline` x4. [COM-goldens](common.md#com-goldens). |

## Copy keys

`backups.*`, `drill.*`, `restore.*`, `confirm.typeHint`. No key yet: the schedule-missed row, "Open server", the row menu items, "Actions for backup …".

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | "Switch back to the previous database" has no podship command (README: "swap the names back"). Proposed: `podship backup restore --undo`, then a tier-2 action here. | podship |
| 2 | Allow restore from a phone? Proposed: no for production (desktop only), yes for drills. | owner |
| 3 | Deleting backups is not a podship command. Not designed. | owner |
