# Copy: Server

| Key | en | es | Notes |
|---|---|---|---|
| server.about | {os}, {arch}, Docker {docker}, compose {compose} | {os}, {arch}, Docker {docker}, compose {compose} | |
| server.resources | Resources | Recursos | |
| server.cpu | CPU: load {load} on {cores} cores | CPU: carga {load} en {cores} núcleos | |
| server.memory | Memory: {used} of {total} used | Memoria: {used} de {total} en uso | |
| server.disk | Disk: {pct} % used, {free} free (backups {backups}) | Disco: {pct} % en uso, {free} libres (respaldos {backups}) | |
| server.registry | Registry | Registro | |
| server.ports | Ports {range}, {count} in use | Puertos {range}, {count} en uso | |
| server.slots | Backup slots | Horarios de respaldo | |
| server.bootstrap | Bootstrap this server | Preparar este servidor | |
| server.bootstrap.body | Installs Docker, compose, age, zstd, the firewall rules and podship's folders. Safe to run again. | Instala Docker, compose, age, zstd, las reglas del firewall y las carpetas de podship. Se puede ejecutar otra vez sin riesgo. | |
| server.bootstrap.confirm | Bootstrap {host} | Preparar {host} | |
| server.unreachable | Can't reach {host} over SSH since {time} ({reason}). Environments on it show last known values. | No se puede conectar por SSH con {host} desde las {time} ({reason}). Sus entornos muestran el último dato. | |
| server.test | Test it from your machine | Pruébalo desde tu máquina | |
| server.macNote | Staging and non-critical apps | Staging y apps no críticas | owner's own label |
| server.provider | Provider | Proveedor | |
| server.provider.none | Added over SSH (no provider) | Agregado por SSH (sin proveedor) | |
| server.provider.renews | Renews on {date} | Se renueva el {date} | |
| server.provider.ends | Ends on {date} (auto-renewal off) | Termina el {date} (renovación automática desactivada) | |
| server.provider.hpanel | Open in hPanel | Abrir en hPanel | |
| server.new | New server | Nuevo servidor | |
| new.how.create | Create a VPS on Hostinger | Crear un VPS en Hostinger | |
| new.how.existing | Add a server I already have | Agregar un servidor que ya tengo | |
| new.name | Name | Nombre | SSH alias |
| new.name.hint | Used as the SSH alias and in every screen. Lowercase letters, digits and -. | Se usa como alias de SSH y en todas las pantallas. Minúsculas, dígitos y -. | |
| new.dc | Data center | Centro de datos | |
| new.dc.noMexico | Hostinger has no data center in Mexico right now. The nearest is preselected. | Hostinger no tiene centro de datos en México por ahora. Se eligió el más cercano. | |
| new.plan | Plan | Plan | |
| new.os | Operating system | Sistema operativo | |
| new.keys | SSH keys | Llaves SSH | |
| new.keys.console | The console's own key is always added. | Siempre se agrega la llave de la consola. | |
| new.firewall | Firewall | Firewall | |
| new.firewall.tunnel | SSH only, web through the Cloudflare Tunnel | Solo SSH, la web por el túnel de Cloudflare | |
| new.firewall.caddy | SSH, HTTP and HTTPS (for Caddy) | SSH, HTTP y HTTPS (para Caddy) | |
| new.tunnel | Create a Cloudflare Tunnel for this server | Crear un túnel de Cloudflare para este servidor | |
| new.providerBackups | Hostinger weekly backups | Respaldos semanales de Hostinger | |
| new.review | Review | Revisar | |
| new.buy | Buy {plan} for {price} per month and set it up | Comprar {plan} por {price} al mes y prepararlo | tier 1, price in the button |
| new.buy.note | Hostinger charges {payment} now. You can stop renewal later; Hostinger's API can't delete a VPS. | Hostinger cobra a {payment} ahora. Después puedes desactivar la renovación; la API de Hostinger no puede borrar un VPS. | |
| new.ready | {name} is ready for projects. | {name} está listo para proyectos. | |
| new.ready.next | From a project folder, run podship launch --env staging with host: {name}. | Desde la carpeta de un proyecto, ejecuta podship launch --env staging con host: {name}. | |
| new.failed.before | Hostinger couldn't set up the VPS: {reason}. Nothing was charged. | Hostinger no pudo preparar el VPS: {reason}. No se cobró nada. | |
| new.failed.after | The VPS exists (id {id}) but bootstrap failed at {step}. | El VPS existe (id {id}) pero la preparación falló en {step}. | |
| new.failed.retry | Retry bootstrap | Reintentar la preparación | |
| destroy.blocked | Move or destroy these environments first: {list} | Primero mueve o elimina estos entornos: {list} | |
| destroy.title | Destroy server {name} | Eliminar el servidor {name} | |
| destroy.steps | Remove the SSH alias and the registry entry · Delete the Cloudflare Tunnel · Stop the VPS · Turn off auto-renewal | Quitar el alias de SSH y la entrada del registro · Borrar el túnel de Cloudflare · Detener el VPS · Desactivar la renovación automática | |
| destroy.limit | Hostinger's API can't delete a VPS. It stays stopped and billed until {date}, then Hostinger removes it. To delete it sooner, use hPanel. | La API de Hostinger no puede borrar un VPS. Queda detenido y se sigue cobrando hasta el {date}; después Hostinger lo elimina. Para borrarlo antes, usa hPanel. | |
| destroy.type | Type {name} to confirm | Escribe {name} para confirmar | |
| destroy.confirm | Destroy {name} | Eliminar {name} | |
