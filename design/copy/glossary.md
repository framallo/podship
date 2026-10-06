# Glossary

Purpose: the console's words in both locales, decided once. Status: draft 2026-10-06. Default locale: en; second: es (Mexican Spanish, tú).

| Term (en) | es | Meaning | Do not use | Example |
|---|---|---|---|---|
| podship, podship console | podship, podship console | Product names | Podship, PodShip | "podship console reads your servers" |
| environment | entorno | One deployment target of a project (`production`, `staging`, any name) | ambiente, stage | "Roll back cazafacturas production" / "Revertir cazafacturas production" |
| `production`, `staging` (environment names) | **not translated** | Identifiers from podship.yaml; lowercase, in the user's own words | producción, Production | "Deploy to production" / "Desplegar a production" |
| project | proyecto | A Serverpod project with a podship.yaml | app, repo | |
| server | servidor | An SSH host (`caza-vps`, `agentes.local`) | máquina, host (except in technical details) | |
| release | versión | One deploy, with an id `YYYYMMDD-HHMMSS-sha7` (UTC) | build, lanzamiento | "Release 20261005-221844-9c41e07" / "Versión 20261005-221844-9c41e07" |
| release id | id de la versión | The id; never translated, always mono | | |
| current release | versión actual | What `current` points to | activa, en vivo | |
| deploy (verb) / deploy (noun) | desplegar / despliegue | Build, upload, switch, health check | publicar, subir | "Deploy main to staging" / "Desplegar main a staging" |
| promote | promover | Run the exact release of one environment on another, no build | copiar | |
| roll back / rollback | revertir / reversión | Switch to an older release (code only unless "with database") | regresar, deshacer | "Roll back to …" / "Revertir a …" |
| roll forward | volver a la versión más nueva | Switch back to the newer release after a rollback | | |
| health check | verificación de salud | The URLs podship fetches after a switch | ping, monitoreo | |
| healthy / unhealthy | en buen estado / con fallas | Health result | sano, caído | |
| backup (noun) / back up (verb) | respaldo / respaldar | `backup now`, schedule | copia de seguridad, backup | |
| restore | restaurar | Replace the database with a backup (old one kept) | recuperar | |
| restore drill | simulacro de restauración | Restore into a throwaway container and compare row counts | prueba | |
| off-site copy | copia fuera del servidor | Encrypted backups pulled to the owner's machine | offsite | |
| variable | variable | A plain `.env` entry whose value may be shown (`plain_env`) | | |
| secret | secreto | A `.env` or `passwords.yaml` entry whose value is never shown | contraseña (unless it is one) | |
| domain | dominio | A hostname routed to the environment | URL | |
| operation | operación | Anything the console runs: deploy, backup, restore… | tarea, job | |
| step | paso | One step of an operation's plan | | |
| test stage, test suite | etapa de pruebas, suite de pruebas | Tests run before build | | |
| skip tests | omitir las pruebas | Deploy without the test stage, with a reason | saltar | |
| owner, deployer, viewer | propietario, puede desplegar, solo lectura | Console roles | admin | Role names in es: "Propietario", "Puede desplegar", "Solo lectura" |
| SSH access | acceso SSH | Keys marked `podship:<name>` on a server | | |
| CI deploy key | llave de despliegue para CI | `ci setup` key | token | |

Never translated: command names, service names (`server`, `postgres`), paths, ports, hostnames, release ids, step titles and log lines from podship, `podship.yaml` keys.
