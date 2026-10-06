# Copy: CLI login, tokens, origins, lock

| Key | en | es | Notes |
|---|---|---|---|
| cli.authorize.title | Authorize the podship CLI on {machine} | Autorizar la CLI de podship en {machine} | |
| cli.authorize.code | Check that your terminal shows this code: {code} | Revisa que tu terminal muestre este código: {code} | |
| cli.authorize.confirm | Authorize CLI | Autorizar CLI | |
| cli.authorize.expired | This code expired. Run podship login again. | Este código venció. Vuelve a ejecutar podship login. | |
| tokens.title | Access tokens | Tokens de acceso | |
| tokens.intro | Tokens let the podship CLI run commands through this console with your permissions or less. | Los tokens permiten que la CLI de podship ejecute comandos a través de esta consola con tus permisos o menos. | |
| tokens.create | Create a token | Crear un token | |
| tokens.col | Name · Scope · Role · Expires · Last used · Created | Nombre · Alcance · Rol · Vence · Último uso · Creado | |
| tokens.lastUsed | {age} ago from {machine} | hace {age} desde {machine} | |
| tokens.never | Never used | Sin usar | |
| tokens.expiresSoon | Expires in {days} days | Vence en {days} días | warn |
| tokens.expired | Expired | Vencido | |
| tokens.dialog.name | Name | Nombre | |
| tokens.dialog.nameHint | Usually the machine, for example federico-mbp | Por lo general la máquina, por ejemplo federico-mbp | |
| tokens.dialog.scope | Projects and environments | Proyectos y entornos | |
| tokens.dialog.role | Role | Rol | |
| tokens.dialog.roleLimit | Your role on {env} is {role} | Tu rol en {env} es {role} | disabled option reason |
| tokens.dialog.expiry | Expires | Vence | |
| tokens.dialog.confirm | Create token | Crear token | |
| tokens.created.title | Token {name} | Token {name} | |
| tokens.created.once | This token is shown once. Copy it now; you can't see it again. | Este token se muestra una sola vez. Cópialo ahora; no lo podrás volver a ver. | |
| tokens.created.use | On the machine, run: podship login {url} --token | En la máquina, ejecuta: podship login {url} --token | |
| tokens.created.done | I saved it | Ya lo guardé | |
| tokens.revoke | Revoke | Revocar | |
| tokens.revoke.title | Revoke token {name} | Revocar el token {name} | |
| tokens.revoke.body | CLI commands that use {name} stop working at once. Operations already running finish. | Los comandos de la CLI que usan {name} dejan de funcionar de inmediato. Las operaciones en curso terminan. | |
| tokens.revoke.confirm | Revoke {name} | Revocar {name} | |
| tokens.nameError | You already have a token named {name}. | Ya tienes un token llamado {name}. | |
| ci.tokens.title | CI tokens for {project} | Tokens de CI para {project} | |
| ci.tokens.create | Create a CI token | Crear un token de CI | |
| ci.tokens.snippet | Add these secrets to your CI: PODSHIP_URL and PODSHIP_TOKEN. Then run podship deploy --env {env} --yes. | Agrega estos secretos a tu CI: PODSHIP_URL y PODSHIP_TOKEN. Luego ejecuta podship deploy --env {env} --yes. | |
| lock.held | {operation} running · held by {person} from {origin} since {time} ({duration}) | {operation} en curso · la tiene {person} desde {origin} desde las {time} ({duration}) | |
| lock.quiet | No events for {duration}. Last event: {time}. | Sin eventos desde hace {duration}. Último evento: {time}. | |
| lock.force | Force release… | Liberar a la fuerza… | owner only |
| lock.force.title | Force release the lock on {project} {env} | Liberar a la fuerza el bloqueo de {project} {env} | |
| lock.force.body | {person}'s {operation} has sent no events for {duration}. If it's still running on {host}, a new operation can collide with it. | La operación {operation} de {person} no envía eventos desde hace {duration}. Si sigue corriendo en {host}, una nueva operación puede chocar con ella. | |
| lock.force.notYet | Available after 5 min without events. | Disponible después de 5 min sin eventos. | |
| lock.force.confirm | Release the lock | Liberar el bloqueo | |
