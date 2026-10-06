# Job stories

Purpose: the jobs the console serves. Status: draft 2026-10-06.
Evidence: all from the owner's brief of 2026-10-06 (no interviews yet). Confidence: heard once.

## Owner (operator, technical, desktop first, checks status from the phone)

| # | Job story | Screens |
|---|---|---|
| J1 | When I open the console in the morning or between tasks, I want to see whether every environment is up and was backed up last night, so I can stop worrying or know where to look. | Overview, phone status flow |
| J2 | When a change is merged, I want to ship it to staging, check it, and then send the exact same release to production, so I can release without rebuilding or guessing. | Environment, Operation |
| J3 | When production breaks after a release, I want to go back to the last good release in seconds, from wherever I am, so I can stop the damage before I debug. | Environment, phone rollback flow, Operation |
| J4 | When I have not tested a backup in a while, I want to restore last night's backup into a throwaway database and see that the row counts match, so I can trust the backups before I need them. | Backups |
| J5 | When data is lost or corrupted, I want to restore a chosen backup without losing the current database, so I can undo the restore if I picked the wrong one. | Backups |
| J6 | When a project needs a new domain or a new secret, I want to add it without logging into the server and without the value ever being shown, so I can keep secrets out of screens and chat. | Domains, Variables and secrets |
| J7 | When something happened that I did not do, I want to see who ran which operation, when, on which release, how long it took and how it ended, so I can explain it. | History, Operation |
| J8 | When I add a server or a project, I want to see what runs on each server, its free resources and the ports and backup slots in use, so I can place the new environment safely. | Server |

## Collaborator (limited access, occasional)

| # | Job story | Screens |
|---|---|---|
| J9 | When I finish a change, I want to deploy it to staging and read its logs, so I can test it without asking the owner for a server login. | Environment (staging), Logs |

## How might we

- HMW make the answer to "is everything up and backed up?" readable in one glance, on a phone?
- HMW make a production rollback take four taps in an emergency and be impossible to trigger by brushing a button?
- HMW show a long operation so the owner can leave and come back and still trust what they see?
