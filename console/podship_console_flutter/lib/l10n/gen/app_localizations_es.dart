// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'podship console';

  @override
  String get signInTitle => 'Entra a podship console';

  @override
  String get signInEmail => 'Correo';

  @override
  String get signInSendCode => 'Enviar código';

  @override
  String get signInCode => 'Código de 6 dígitos';

  @override
  String get signInVerify => 'Entrar';

  @override
  String signInCodeSent(Object email) {
    return 'Si $email puede usar esta consola, ya va un código en camino.';
  }

  @override
  String get signInNoMail =>
      'Esta consola todavía no puede enviar correos. Pide al propietario un enlace para entrar.';

  @override
  String get signInBadCode =>
      'Este código es incorrecto o venció. Pide uno nuevo.';

  @override
  String get signInBadEmail => 'Escribe un correo como nombre@ejemplo.com.';

  @override
  String get signInTooMany => 'Demasiados intentos. Espera unos minutos.';

  @override
  String get signInLinkUsed =>
      'Este enlace ya se usó o venció. Pide uno nuevo.';

  @override
  String get signInLinkWorking => 'Entrando…';

  @override
  String get signOut => 'Salir';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get settingsIntegrations => 'Integraciones';

  @override
  String get intTitle => 'Integraciones';

  @override
  String intLead(Object workspace) {
    return 'Conecta cada proveedor una vez. Todos los proyectos de $workspace usan la conexión.';
  }

  @override
  String get intStatusOff => 'Sin conectar';

  @override
  String get intStatusOn => 'Conectado';

  @override
  String get intStatusWaiting => 'Esperando a AWS';

  @override
  String get intConnect => 'Conectar';

  @override
  String get intDisconnect => 'Desconectar…';

  @override
  String get intCfWhat =>
      'Registros DNS, rutas del túnel y Access de tus dominios.';

  @override
  String get intCfStep1 => 'En la pestaña de Cloudflare: Continue to summary.';

  @override
  String get intCfStep2 => 'Create Token.';

  @override
  String get intCfStep3 =>
      'Copy. Luego pega el token aquí: podship lo verifica y lo guarda en ese momento.';

  @override
  String get intCfField => 'Token de API de Cloudflare';

  @override
  String get intCfSave => 'Guardar y verificar';

  @override
  String get intCfReopen => 'Abrir Cloudflare otra vez';

  @override
  String get intCfEmpty => 'Pega el token que copiaste en Cloudflare.';

  @override
  String get intCfInactive =>
      'Cloudflare dice que este token no está activo. Crea uno nuevo.';

  @override
  String intCfMissing(Object permission) {
    return 'Este token no puede $permission. Créalo otra vez desde el enlace, sin cambiar los permisos.';
  }

  @override
  String get intCfInvalid =>
      'Cloudflare no reconoce este token. Revisa que lo pegaste completo.';

  @override
  String intCfAccount(Object name, Object zones) {
    return 'Cuenta $name · $zones zonas';
  }

  @override
  String get intPermissions => 'Lo que podship puede hacer';

  @override
  String get intCfPerm1 =>
      'Zone: Read · DNS: Edit · SSL and Certificates: Read';

  @override
  String get intCfPerm2 =>
      'Account: Cloudflare Tunnel: Edit · Access: Apps and Policies: Edit';

  @override
  String get intCfRevokeHint =>
      'Borra también el token \"podship console\" en Cloudflare. podship no puede borrarlo por ti.';

  @override
  String get intCfRevokeLink => 'Tokens de API de Cloudflare';

  @override
  String get intAwsWhat =>
      'Envío de correo con Amazon SES: dominios, DKIM y un usuario de envío por app.';

  @override
  String get intAwsStep1 =>
      'En la pestaña de AWS: inicia sesión si AWS lo pide.';

  @override
  String get intAwsStep2 =>
      'Abajo, marca la casilla que acepta los recursos de IAM.';

  @override
  String get intAwsStep3 =>
      'Haz clic en \"Create stack\". Esta tarjeta cambia a Conectado sola.';

  @override
  String intAwsWaiting(Object time) {
    return 'Esperando la pila desde las $time. Esta página se actualiza sola.';
  }

  @override
  String get intAwsAgain => 'Abrir AWS otra vez';

  @override
  String get intAwsAccount => 'Cuenta';

  @override
  String get intAwsRole => 'Rol';

  @override
  String get intAwsSes => 'SES';

  @override
  String intAwsSesMode(Object mode, Object region) {
    return '$region: $mode';
  }

  @override
  String get intAwsSesProd => 'acceso de producción';

  @override
  String get intAwsSesSandbox => 'sandbox';

  @override
  String get intAwsNoKeys => 'podship usa un rol. No existen llaves de acceso.';

  @override
  String get intAwsPerm1 =>
      'SES: identidades, DKIM, MAIL FROM, enviar una prueba';

  @override
  String get intAwsPerm2 =>
      'IAM: usuarios en /podship-ses/ que solo pueden enviar correo';

  @override
  String get intAwsRevokeHint =>
      'Borra la pila \"podship\" en CloudFormation para quitar el rol.';

  @override
  String get intAwsRevokeLink => 'Pilas de CloudFormation';

  @override
  String get intToken => 'Token';

  @override
  String intTokenEnds(Object hint) {
    return 'termina en $hint';
  }

  @override
  String get intConnectedLabel => 'Conectado';

  @override
  String intConnectedBy(Object date, Object person) {
    return 'por $person el $date';
  }

  @override
  String get intLastCheck => 'Última verificación';

  @override
  String intCheckFailed(Object provider, Object time) {
    return 'podship no pudo comunicarse con $provider a las $time. La conexión sigue guardada.';
  }

  @override
  String get intOnlyAdmins =>
      'Solo los propietarios y administradores del espacio de trabajo pueden conectar o desconectar proveedores.';

  @override
  String intDisconnectTitle(Object provider) {
    return '¿Desconectar $provider?';
  }

  @override
  String intDisconnectCf(Object workspace) {
    return 'podship deja de cambiar DNS, túneles y Access en todos los proyectos de $workspace. Tus sitios siguen funcionando.';
  }

  @override
  String intDisconnectAws(Object workspace) {
    return 'podship deja de configurar el correo en todos los proyectos de $workspace. Las apps siguen enviando con sus propios usuarios de envío.';
  }

  @override
  String get intDisconnectConfirm => 'Desconectar';

  @override
  String intDisconnected(Object provider) {
    return '$provider está desconectado.';
  }

  @override
  String intConnectedNow(Object provider) {
    return '$provider está conectado.';
  }

  @override
  String intAwsFailed(Object error) {
    return 'AWS respondió, pero podship no pudo usar el rol: $error. Descarga la plantilla otra vez y actualiza la pila.';
  }

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonNewTab => '(se abre en una pestaña nueva)';

  @override
  String get commonError => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get commonForbidden => 'No tienes acceso a esto.';

  @override
  String get intAwsNotReady =>
      'AWS todavía no se puede conectar: la plantilla de podship no está publicada. Pregunta al responsable de podship.';

  @override
  String get intCfChecking => 'Verificando el token…';
}
