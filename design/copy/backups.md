# Copy: Backups

| Key | en | es | Notes |
|---|---|---|---|
| backups.title | Backups | Respaldos | |
| backups.action.drill | Run a restore drill | Hacer un simulacro de restauración | primary |
| backups.action.now | Back up now | Respaldar ahora | |
| backups.action.restore | Restore… | Restaurar… | |
| backups.action.pull | Pull to this Mac | Traer a esta Mac | when off-site configured |
| backups.schedule | Daily at {time} {zone} ({unit}) | Diario a las {time} {zone} ({unit}) | |
| backups.retention | Today and yesterday, then {d} daily, {w} weekly and {m} monthly | Hoy y ayer, luego {d} diarios, {w} semanales y {m} mensuales | |
| backups.encryption | Encrypted to {count} SSH keys: {names} | Cifrados para {count} llaves SSH: {names} | |
| backups.offsite | Pulled to {dir} on {machine}. Newest pulled {time}; it decrypts and its checksums match. | Se traen a {dir} en {machine}. El más reciente llegó a las {time}; se descifra y sus sumas coinciden. | |
| backups.lastDrill | {date}: {n} tables match, {v} volatile tables differ as expected | {date}: {n} tablas coinciden, {v} tablas volátiles difieren como se espera | |
| backups.col.stamp | Backup | Respaldo | |
| backups.col.size | Size | Tamaño | |
| backups.col.contents | Contents | Contenido | |
| backups.col.origin | Origin | Origen | |
| backups.origin.scheduled | Scheduled | Programado | |
| backups.origin.beforeDeploy | Before deploy {id} | Antes del despliegue {id} | |
| backups.origin.manual | Manual, by {person} | Manual, por {person} | |
| drill.verdict.ok | Backup {stamp} restores. {n} of {n} tables match; {v} volatile tables differ ({names}). | El respaldo {stamp} se restaura. {n} de {n} tablas coinciden; {v} tablas volátiles difieren ({names}). | |
| drill.verdict.fail | Backup {stamp} restored, but {count} tables don't match: {names}. Don't rely on it; check the backup log. | El respaldo {stamp} se restauró, pero {count} tablas no coinciden: {names}. No confíes en él; revisa el registro del respaldo. | |
| drill.col | Table · Rows at backup · Restored · Live now · Result | Tabla · Filas al respaldar · Restauradas · Ahora · Resultado | |
| restore.step1.title | Restore {project} {env}: choose a backup | Restaurar {project} {env}: elige un respaldo | |
| restore.step1.order | What happens, in order | Qué pasa, en orden | |
| restore.step1.list | Take a fresh backup · Stop the app services · Rename the database to {kept} · Restore into a new database · Start the services and wait for health | Hacer un respaldo nuevo · Detener los servicios de la app · Renombrar la base de datos a {kept} · Restaurar en una base de datos nueva · Iniciar los servicios y esperar la verificación de salud | |
| restore.step1.upload | Upload a .dump file instead | Mejor subir un archivo .dump | desktop only |
| restore.step1.next | Continue | Continuar | |
| restore.dialog.title | Restore {project} {env} from {stamp} | Restaurar {project} {env} desde {stamp} | |
| restore.dialog.consequence | The app is down while the restore runs, about {minutes} min for a {size} database. The current database is kept as {kept}. | La app no funciona mientras se restaura, unos {minutes} min para una base de datos de {size}. La base de datos actual se conserva como {kept}. | |
| restore.dialog.confirm | Restore {env} | Restaurar {env} | |
| restore.done | {env} runs on the database from {stamp}. Health check passed. | {env} funciona con la base de datos de {stamp}. La verificación de salud pasó. | |
| restore.done.kept | The previous database is kept as {kept}. To switch back, swap the names (command below). | La base de datos anterior se conserva como {kept}. Para regresar, intercambia los nombres (comando abajo). | |
| backups.empty.title | No backups yet | Aún no hay respaldos | |
| backups.empty.body | Schedule a daily backup or take one now. podship picks a free time slot on {host}. | Programa un respaldo diario o haz uno ahora. podship elige un horario libre en {host}. | |
| backups.empty.action | Schedule daily backups | Programar respaldos diarios | |
| backups.failed | Backup of {date} failed: {reason} | El respaldo del {date} falló: {reason} | |
