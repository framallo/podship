# Copy: Environment

| Key | en | es | Notes |
|---|---|---|---|
| env.band | {env} · {host} · release {id} | {env} · {host} · versión {id} | band; env never translated |
| env.tab.releases | Releases | Versiones | |
| env.tab.backups | Backups | Respaldos | |
| env.tab.variables | Variables | Variables | |
| env.tab.domains | Domains | Dominios | |
| env.tab.logs | Logs | Registros | |
| env.tab.database | Database | Base de datos | |
| env.action.deploy | Deploy {ref} to {env} | Desplegar {ref} a {env} | |
| env.action.promote | Promote from {from} | Promover desde {from} | |
| env.action.rollbackTo | Roll back to {id} | Revertir a {id} | primary when unhealthy |
| env.action.rollback | Roll back… | Revertir… | secondary |
| env.action.restart | Restart | Reiniciar | |
| env.current.title | Current release | Versión actual | |
| env.current.by | Deployed by {person} {age} ago, in {duration} | Desplegada por {person} hace {age}, en {duration} | |
| env.releases.title | Releases | Versiones | |
| env.releases.origin.deploy | Deploy | Despliegue | |
| env.releases.origin.promote | Promoted from {env} | Promovida desde {env} | |
| env.releases.origin.rollback | Rollback | Reversión | |
| env.releases.origin.adopt | Adopted | Adoptada | |
| env.releases.failedNote | Failed health check on {date}. podship switched back. | Falló la verificación de salud el {date}. podship regresó a la anterior. | |
| env.releases.menu.rollback | Roll back to this release… | Revertir a esta versión… | |
| env.releases.menu.copy | Copy id | Copiar id | |
| env.unhealthy.banner | Health check failing for {duration}. {url}: {reason} | La verificación de salud falla desde hace {duration}. {url}: {reason} | |
| env.unhealthy.hint | Roll back to the last healthy release first, then read the logs. | Primero revierte a la última versión en buen estado y luego revisa los registros. | |
| deploy.dialog.title | Deploy {project} to {env} | Desplegar {project} a {env} | |
| deploy.dialog.ref | Branch, tag or commit | Rama, etiqueta o commit | label |
| deploy.dialog.resolved | {ref} is at {sha}: {message} | {ref} está en {sha}: {message} | |
| deploy.dialog.refError | No branch, tag or commit named {ref}. Check the name. | No hay rama, etiqueta ni commit llamado {ref}. Revisa el nombre. | on blur |
| deploy.dialog.consequence | The app restarts on the new release. If the health check fails, podship switches back on its own. | La app se reinicia con la nueva versión. Si falla la verificación de salud, podship regresa a la anterior por su cuenta. | |
| deploy.dialog.steps | What runs | Qué se ejecuta | |
| deploy.dialog.skipBackup | Skip the backup before the switch | Omitir el respaldo antes del cambio | |
| deploy.dialog.confirm | Deploy to {env} | Desplegar a {env} | |
| rollback.dialog.title | Roll back {project} {env} | Revertir {project} {env} | |
| rollback.dialog.target | Release to run | Versión que se va a ejecutar | |
| rollback.dialog.default | Newest healthy release before the current one | Versión en buen estado más reciente antes de la actual | |
| rollback.dialog.other | Choose another release | Elegir otra versión | |
| rollback.dialog.consequence | The app restarts on the older release, usually in under a minute. The database stays as it is: migrations from newer releases are not undone. | La app se reinicia con la versión anterior, por lo general en menos de un minuto. La base de datos no cambia: las migraciones de versiones más nuevas no se deshacen. | |
| rollback.dialog.withDb | Also restore the database from a backup | También restaurar la base de datos desde un respaldo | switches to tier 2 |
| rollback.dialog.confirm | Roll back {env} to {id} | Revertir {env} a {id} | |
| rollback.done.forward | Roll forward to {id} | Volver a {id} | |
| promote.dialog.title | Promote to {env} | Promover a {env} | |
| promote.dialog.body | Runs on {to} the exact release that runs on {from}: the same files and images, no build. | Ejecuta en {to} exactamente la versión que corre en {from}: los mismos archivos e imágenes, sin compilar. | |
| promote.dialog.confirm | Promote {id} to {env} | Promover {id} a {env} | |
| promote.blocked.arch | {from_host} is {from_arch} and {to_host} is {to_arch}, so the images can't move. Deploy commit {sha} to {env} instead. | {from_host} es {from_arch} y {to_host} es {to_arch}, así que las imágenes no se pueden mover. Mejor despliega el commit {sha} a {env}. | |
| promote.blocked.action | Deploy {sha} to {env} | Desplegar {sha} a {env} | |
| env.readOnly | Only the owner can change {env}. You can read its status, releases and logs. | Solo el propietario puede cambiar {env}. Puedes ver su estado, versiones y registros. | collaborator |
| db.title | Database | Base de datos | |
| db.migrations | Migrations | Migraciones | |
| db.migrations.upToDate | All {count} migrations applied. Newest in the release: {name}. | Las {count} migraciones están aplicadas. La más nueva de la versión: {name}. | |
| db.connect | Connect from your machine | Conectarte desde tu máquina | |
| db.users | Database users | Usuarios de la base de datos | |
