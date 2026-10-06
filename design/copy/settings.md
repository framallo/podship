# Copy: Settings (people, SSH access, CI keys, preferences)

| Key | en | es | Notes |
|---|---|---|---|
| settings.people | People | Personas | |
| settings.access | SSH access | Acceso SSH | |
| settings.tokens | Access tokens | Tokens de acceso | see cli-and-tokens.md |
| settings.ci | CI keys | Llaves de CI | |
| settings.preferences | Preferences | Preferencias | |
| people.invite | Invite a person | Invitar a una persona | |
| people.role.owner | Owner | Propietario | |
| people.role.deployer | Deployer | Despliega | |
| people.role.viewer | Viewer | Solo lectura | |
| people.scope | {role} on {scope} | {role} en {scope} | scope = project or project/env |
| people.separate | Console roles and SSH access are separate: a role doesn't give an SSH login, and an SSH key doesn't give a console sign-in. | Los roles de la consola y el acceso SSH son independientes: un rol no da acceso por SSH y una llave SSH no da acceso a la consola. | |
| access.add | Add an SSH key | Agregar una llave SSH | |
| access.keyError | This isn't an SSH public key. It starts with ssh-ed25519 or ssh-rsa. | Esto no es una llave pública SSH. Empieza con ssh-ed25519 o ssh-rsa. | on blur |
| access.remove.title | Remove {name}'s SSH access | Quitar el acceso SSH de {name} | |
| access.remove.body | Removes the key marked podship:{name} from {servers}. Open sessions stay open until they end. | Quita la llave marcada podship:{name} de {servers}. Las sesiones abiertas siguen hasta que terminen. | |
| access.remove.type | Type {name} to confirm | Escribe {name} para confirmar | tier 2 |
| access.remove.confirm | Remove access | Quitar acceso | |
| ci.created.title | Deploy key for {project} {env} | Llave de despliegue para {project} {env} | |
| ci.created.once | This private key is shown once. Save it as the CI secret PODSHIP_SSH_KEY now. | Esta llave privada se muestra una sola vez. Guárdala ahora como el secreto de CI PODSHIP_SSH_KEY. | |
| ci.created.done | I saved it | Ya la guardé | |
| prefs.language | Language | Idioma | |
| prefs.theme | Theme | Tema | System, Light, Dark / Sistema, Claro, Oscuro |
| prefs.timezone | Time zone | Zona horaria | |
