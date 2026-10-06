# Assumptions (the interview, answered from the brief)

Purpose: the discovery interview for the console, answered by the designer from the owner's brief because the owner asked not to wait. Each line is an assumption to confirm, not a finding. Status: open, 2026-10-06.

| # | Question | Assumption | Type | Importance | Evidence | How to test |
|---|---|---|---|---|---|---|
| 1 | Default language and locales? | English default (open-source tool, English CLI and README); Spanish second, written in Mexican Spanish with tú. | viable | high | README and CLI are English; the owner's products ship en + es | Owner confirms |
| 2 | Job story for the most frequent visit? | J1: "is everything up and backed up?" | desirable | high | Brief | Count visits per screen after launch |
| 3 | Who else touches the result? | A collaborator with limited access; CI (deploys with a key, appears in history as `ci:<name>`); people with SSH keys on servers. | desirable | high | Brief, `access` and `ci setup` commands | Owner confirms the roles |
| 4 | What does the owner fear at that moment? | Running an operation on production by mistake; a rollback that also needs the database; a restore that destroys the live data; a secret on screen. | desirable | high | Brief; the CLI defaults destructive commands to staging | Owner confirms |
| 5 | How do they know it worked? | The health check passes (server URL, then public URL); the operation ends "Succeeded" with the release id; the drill compares row counts. | feasible | high | `HealthStep`, `restore.sh drill` | Built behavior |
| 6 | Which actions are irreversible? | None is fully irreversible by design (restore renames the old database, rollback keeps releases), but these lose data or availability: restore, rollback with database, `db wipe`, `destroy`, removing a person's access, deleting backups. | feasible | high | README | Owner confirms the list |
| 7 | Where does the console run? | A Serverpod server on a machine that already has SSH access to the servers (the owner's Mac, or a small control host), reached by the phone through a tunnel. One console per owner. | feasible | high | none | Owner decides; open question in `specs/settings.md` |
| 8 | How do people sign in? | A passkey on a local install (no mail sender needed); email codes (6 digits, as CazaFacturas) when a mail sender is configured. Roles per person: owner, deployer, viewer, per project or environment. | viable | medium | CazaFacturas auth provider; `specs/first-run.md` | Owner decides (open) |
| 9 | Desktop or phone first? | Desktop first for every job; the phone covers J1 (status) and J3 (rollback) completely and shows the rest read-only. | desirable | high | Brief | Owner confirms |
| 10 | How will we measure success? | Time from opening the app to a running production rollback (target: under 20 s, 4 taps); share of environments with a drill in the last 30 days; no operation run on the wrong environment. | viable | medium | none | Instrument the console server |
| 11 | Do operations need to keep running when the browser closes? | Yes. Operations run on the console server; closing the view never stops one. There is no cancel (podship's executor has none). | feasible | high | `Executor.run` has no cancellation; the `d837f54` event API has none either | Owner confirms that "no cancel" is acceptable |
| 12 | Notifications? | Out of scope for this round. A failed scheduled backup or an automatic rollback should reach the owner (email or push); listed as an open question. | desirable | medium | none | Owner decides |
