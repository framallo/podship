# Common strings (shell, states, errors)

Status: draft 2026-10-06. Keys map to ARB keys (`common.retry` → `commonRetry`).

| Key | en | es | Notes |
|---|---|---|---|
| nav.overview | Overview | Resumen | |
| nav.projects | Projects | Proyectos | |
| nav.servers | Servers | Servidores | |
| nav.operations | Operations | Operaciones | phone bottom nav |
| nav.history | History | Historial | |
| nav.settings | Settings | Configuración | |
| shell.search | Search or run a command | Buscar o ejecutar un comando | palette field |
| shell.running | {count, plural, one{1 operation running} other{# operations running}} | {count, plural, one{1 operación en curso} other{# operaciones en curso}} | top bar |
| common.retry | Retry now | Reintentar ahora | |
| common.cancel | Cancel | Cancelar | dismissive, always left |
| common.close | Close | Cerrar | |
| common.copy | Copy | Copiar | |
| common.copied | Copied | Copiado | polite announcement |
| common.save | Save | Guardar | |
| common.lastKnown | last known | último dato | appended to stale values |
| common.ago | {time} ago | hace {time} | relative ages |
| state.loading | Checking {count} servers… | Revisando {count} servidores… | |
| state.stale | Showing data from {time}. Can't reach the console server. Retrying in {seconds} s. | Datos de las {time}. No se puede conectar con el servidor de la consola. Reintento en {seconds} s. | |
| state.offline | You're offline. Showing data from {time}. | No tienes conexión. Datos de las {time}. | |
| state.reconnecting | Reconnecting… The operation keeps running on the server. | Reconectando… La operación sigue en el servidor. | |
| state.serverUnreachable | Can't reach {host} over SSH since {time} ({reason}). | No se puede conectar por SSH con {host} desde las {time} ({reason}). | reason from ssh, English |
| state.forbidden | You don't have permission to {action} on {env}. Ask {owner} for access. | No tienes permiso para {action} en {env}. Pide acceso a {owner}. | |
| state.notFound | {project} has no environment named {name}. Environments: {list}. | {project} no tiene un entorno llamado {name}. Entornos: {list}. | |
| state.serverError | Something failed on the console server. Try again; if it keeps failing, check its logs. | Algo falló en el servidor de la consola. Vuelve a intentarlo; si sigue fallando, revisa sus registros. | |
| state.signedOut | Your session ended. Sign in again to continue. | Tu sesión terminó. Vuelve a entrar para continuar. | |
| lock.running | {operation} running, started {time} by {person}. | {operation} en curso, iniciada {time} por {person}. | reason on disabled actions |
| lock.open | Open operation | Abrir operación | |
| health.healthy | Healthy | En buen estado | |
| health.unhealthy | Unhealthy | Con fallas | |
| health.unknown | Unknown | Sin datos | |
| pill.running | Running | En curso | |
| pill.succeeded | Succeeded | Terminó bien | |
| pill.failed | Failed | Falló | |
| pill.recovered | Recovered | Recuperado | auto-rollback |
| pill.blocked | Blocked by tests | Bloqueado por pruebas | |
| confirm.typeHint | Type {target} to confirm | Escribe {target} para confirmar | tier 2 |
| confirm.runsToEnd | This runs to the end even if you close the console. | Se ejecuta hasta el final aunque cierres la consola. | |
