import 'dart:io';

import 'package:serverpod_auth_idp_server/core.dart';

import 'src/auth/email_code_idp.dart';
import 'src/core/app_config.dart';
import 'src/generated/serverpod.dart';
import 'src/web/routes/app_config_route.dart';
import 'src/web/routes/console_routes.dart';
import 'src/workspace/workspace_service.dart';

/// Starts the podship console server.
void run(List<String> args) async {
  final pod = Serverpod(args);
  final config = AppConfig.load(pod);
  stdout.writeln(
    'podship console: mode=${config.runMode} url=${config.publicUrl} '
    'workspace="${config.workspaceName}" owners=${config.ownerEmails.length} '
    'mail=${config.mailFrom == null ? 'links only' : 'ses'}',
  );

  pod.initializeAuthServices(
    tokenManagerBuilders: [JwtConfigFromPasswords()],
    identityProviderBuilders: [
      EmailCodeIdpConfig(
        hashPepper: pod.getPassword('emailSecretHashPepper') ?? 'podship',
      ),
    ],
  );

  pod.webServer.addRoute(HealthRoute(), '/health');
  pod.webServer.addRoute(
    OidcDiscoveryRoute(),
    '/.well-known/openid-configuration',
  );
  pod.webServer.addRoute(JwksRoute(), '/.well-known/jwks.json');
  pod.webServer.addRoute(AwsCallbackRoute(), '/integrations/aws/callback');
  pod.webServer.addRoute(PodshipApiRoute(), '/podship/v1/**');
  pod.webServer.addRoute(InternalSignInLinkRoute(), '/internal/sign-in-link');
  pod.webServer.addRoute(
    InternalAccessTokenRoute(),
    '/internal/access-token',
  );
  pod.webServer.addRoute(
    AppConfigRoute(pod.config.apiServer),
    '/assets/assets/config.json',
  );

  final appDir = Directory(Uri(path: 'web/app').toFilePath());
  if (appDir.existsSync()) {
    pod.webServer.addRoute(
      FlutterRoute(appDir, enableWasmHeaders: false),
      '/',
    );
  }

  await pod.start();

  final s = await pod.createSession(enableLogging: false);
  try {
    await WorkspaceService.ensure(s);
  } finally {
    await s.close();
  }
}
