# Backups spec: reasons

Status: accepted 2026-10-06 (moved out of `specs/backups.md` on 2026-10-07). Decided by: owner and designer.

Context: the spec body holds rules only. The reasons below came from the spec text.

| Rule | Decision | Why |
|---|---|---|
| BAK-1 | "Run a restore drill" is the primary action. | It proves the backups work, and it is the job most often skipped. |
| BAK-11 | No error message after a wrong typed confirmation. | The button stays disabled until the text matches, so an error is not needed. |
| BAK-13 | A restore is tier 2 on every environment, staging included. | The CLI asks for the project name on every environment. |
| Purpose | Restore must be provably safe and impossible to start by accident. | The "How might we" of J1, J4, J5. |
