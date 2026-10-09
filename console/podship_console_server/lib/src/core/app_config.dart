import 'dart:io';

import 'package:serverpod/serverpod.dart';

import 'vault.dart';

/// The console's settings: environment variables and passwords.yaml, read
/// once at start.
///
/// | Variable | Meaning |
/// |---|---|
/// | `CONSOLE_PUBLIC_URL` | The public origin, for example `https://podship.densitylabs.io`. It is also the OIDC issuer that AWS trusts. |
/// | `CONSOLE_OWNER_EMAILS` | Comma-separated: these people are owners of the workspace. |
/// | `CONSOLE_WORKSPACE` | The workspace name (default `Density Labs`). |
/// | `CONSOLE_MAIL_FROM` | Optional: the sender of sign-in codes, through the workspace's AWS integration. |
/// | `CONSOLE_SES_REGION` | The SES region (default `us-west-1`). |
/// | `CONSOLE_AWS_TEMPLATE_URL` | The public S3 URL of the connect template (`https://podship-templates-<account>.s3.us-west-1.amazonaws.com/aws/connect-v1.json`). Without it AWS cannot connect. |
///
/// passwords.yaml: `integrationKey` (32 bytes, base64), `serviceSecret`,
/// `emailSecretHashPepper` and the JWT passwords.
class AppConfig {
  AppConfig._({
    required this.runMode,
    required this.publicUrl,
    required this.ownerEmails,
    required this.workspaceName,
    required this.mailFrom,
    required this.sesRegion,
    required this.vault,
    this.awsTemplateUrl,
  });

  static AppConfig? _instance;
  static AppConfig get instance =>
      _instance ?? (throw StateError('AppConfig.load was not called'));

  /// For tests.
  static set instance(AppConfig c) => _instance = c;

  factory AppConfig.load(Serverpod pod, {Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final key = pod.getPassword('integrationKey');
    if (key == null || key.isEmpty) {
      throw StateError('passwords.yaml has no integrationKey');
    }
    final web = pod.config.webServer;
    final fallback = web == null
        ? 'http://localhost:8082'
        : '${web.publicScheme}://${web.publicHost}'
              '${(web.publicPort == 443 || web.publicPort == 80) ? '' : ':${web.publicPort}'}';
    return _instance = AppConfig._(
      runMode: pod.runMode,
      publicUrl: _trim(env['CONSOLE_PUBLIC_URL'] ?? fallback),
      ownerEmails: (env['CONSOLE_OWNER_EMAILS'] ?? '')
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet(),
      workspaceName: env['CONSOLE_WORKSPACE'] ?? 'Density Labs',
      mailFrom: env['CONSOLE_MAIL_FROM'],
      sesRegion: env['CONSOLE_SES_REGION'] ?? 'us-west-1',
      vault: Vault.fromBase64(key),
      awsTemplateUrl: (env['CONSOLE_AWS_TEMPLATE_URL'] ?? '').isEmpty
          ? null
          : env['CONSOLE_AWS_TEMPLATE_URL'],
    );
  }

  /// For tests.
  factory AppConfig.forTest({
    String publicUrl = 'https://console.test',
    Set<String> ownerEmails = const {'owner@example.com'},
    required List<int> key,
    String? awsTemplateUrl =
        'https://podship-templates-123456789012.s3.us-west-1.amazonaws.com/aws/connect-v1.json',
  }) => _instance = AppConfig._(
    runMode: 'test',
    publicUrl: publicUrl,
    ownerEmails: ownerEmails,
    workspaceName: 'Test Workspace',
    mailFrom: null,
    sesRegion: 'us-west-1',
    vault: Vault(key),
    awsTemplateUrl: awsTemplateUrl,
  );

  static String _trim(String u) =>
      u.endsWith('/') ? u.substring(0, u.length - 1) : u;

  final String runMode;
  final String publicUrl;
  final Set<String> ownerEmails;
  final String workspaceName;
  final String? mailFrom;
  final String sesRegion;
  final Vault vault;
  final String? awsTemplateUrl;

  bool get isDevelopment => runMode == 'development';
  bool get isTest => runMode == 'test';

  /// The host part of the issuer, as AWS writes it in condition keys.
  String get issuerHost => Uri.parse(publicUrl).authority;
}
