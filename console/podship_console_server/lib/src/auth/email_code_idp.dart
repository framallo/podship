// ignore_for_file: prefer_initializing_formals

import 'dart:math';

import 'package:clock/clock.dart';
import 'package:podship/podship.dart' show SesApi;
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_idp_server/core.dart';

import '../core/app_config.dart';
import '../core/secrets.dart';
import '../generated/protocol.dart';
import '../integrations/integration_service.dart';
import '../workspace/workspace_service.dart';

/// Sign in with a 6-digit code sent by email, or with a one-time link made
/// on the server (the Boceto pattern; decision: integrations phase 1).
/// Only workspace members can sign in. For anyone else [requestCode] answers
/// as if it worked and sends nothing.
class EmailCodeIdpConfig extends IdentityProviderBuilder<EmailCodeIdp> {
  const EmailCodeIdpConfig({
    required this.hashPepper,
    this.codeLifetime = const Duration(minutes: 10),
    this.maxAttempts = 5,
    this.codeGenerator,
  });
  final String hashPepper;
  final Duration codeLifetime;
  final int maxAttempts;

  /// For tests.
  final String Function()? codeGenerator;

  @override
  EmailCodeIdp build({
    required TokenManager tokenManager,
    required AuthUsers authUsers,
    required UserProfiles userProfiles,
  }) => EmailCodeIdp(this, tokenManager: tokenManager, authUsers: authUsers);
}

class EmailCodeIdp implements IdentityProvider {
  EmailCodeIdp(
    this.config, {
    required TokenManager tokenManager,
    required AuthUsers authUsers,
  }) : _tokenManager = tokenManager,
       _authUsers = authUsers,
       _hash = Argon2HashUtil(
         hashPepper: config.hashPepper,
         hashSaltLength: 16,
       ),
       _emailLimiter = DatabaseRateLimiter(
         RateLimiterConfig(
           domain: 'email_code',
           source: 'request_email',
           maxAttempts: 5,
           timeframe: const Duration(hours: 1),
         ),
       );

  @override
  String get method => 'email_code';

  final EmailCodeIdpConfig config;
  final TokenManager _tokenManager;
  final AuthUsers _authUsers;
  final Argon2HashUtil _hash;
  final DatabaseRateLimiter _emailLimiter;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static String normalize(String email) => email.trim().toLowerCase();

  static String randomCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static Future<bool> hasAccess(Session session, String email) async {
    final ws = await WorkspaceService.ensure(session);
    return await WorkspaceService.roleOf(session, ws, email) != null;
  }

  /// Sends a code through the workspace's AWS integration and
  /// `CONSOLE_MAIL_FROM`. Without them it says so: the person uses a link.
  Future<void> requestCode(
    Session session,
    String rawEmail, {
    String locale = 'en',
  }) async {
    final email = normalize(rawEmail);
    if (!_emailRe.hasMatch(email)) {
      throw EmailCodeException(reason: EmailCodeFailure.invalidEmail);
    }
    if (!await _emailLimiter.tryRecordAttempt(session, key: email)) {
      throw EmailCodeException(reason: EmailCodeFailure.tooManyAttempts);
    }
    final cfg = AppConfig.instance;
    final from = cfg.mailFrom;
    final canMail = from != null || cfg.isDevelopment || cfg.isTest;
    if (!canMail) {
      throw EmailCodeException(reason: EmailCodeFailure.deliveryFailed);
    }
    if (!await hasAccess(session, email)) {
      session.log('email_code: $email is not a member; nothing sent');
      return;
    }
    final code = config.codeGenerator?.call() ?? randomCode();
    final now = clock.now();
    await EmailCodeRequest.db.deleteWhere(
      session,
      where: (t) => t.email.equals(email),
    );
    await EmailCodeRequest.db.insertRow(
      session,
      EmailCodeRequest(
        email: email,
        codeHash: await _hash.createHashFromString(secret: code),
        expiresAt: now.add(config.codeLifetime),
        locale: locale.toLowerCase().startsWith('es') ? 'es-MX' : 'en',
      ),
    );
    if (cfg.isDevelopment || cfg.isTest) {
      session.log('email_code: code for $email -> $code');
      if (from == null) return;
    }
    try {
      final ws = await WorkspaceService.ensure(session);
      final sts = await IntegrationService.assumeAws(session, ws);
      final es = locale.toLowerCase().startsWith('es');
      await SesApi(sts.credentials, region: cfg.sesRegion).send(
        from: from!,
        to: [email],
        subject: es
            ? 'Tu código de podship console: $code'
            : 'Your podship console code: $code',
        text: es
            ? 'Tu código para entrar a podship console es $code.\n'
                  'Vence en 10 minutos. Si no lo pediste, ignora este correo.'
            : 'Your code to sign in to podship console is $code.\n'
                  'It expires in 10 minutes. If you did not ask for it, '
                  'ignore this email.',
      );
    } on Object catch (e) {
      session.log('email_code: the code for $email did not go out: $e');
      throw EmailCodeException(reason: EmailCodeFailure.deliveryFailed);
    }
  }

  Future<AuthSuccess> verifyCode(
    Session session,
    String rawEmail,
    String code,
  ) async {
    final email = normalize(rawEmail);
    final request = (await EmailCodeRequest.db.find(
      session,
      where: (t) => t.email.equals(email) & t.consumedAt.equals(null),
      orderByList: (t) => [t.createdAt.desc()],
      limit: 1,
    )).firstOrNull;
    if (request == null) {
      throw EmailCodeException(reason: EmailCodeFailure.notFound);
    }
    if (request.attempts >= config.maxAttempts) {
      throw EmailCodeException(reason: EmailCodeFailure.tooManyAttempts);
    }
    final ok = await _hash.validateHashFromString(
      secret: code.trim(),
      hashString: request.codeHash,
    );
    if (!ok) {
      await EmailCodeRequest.db.updateRow(
        session,
        request.copyWith(attempts: request.attempts + 1),
      );
      throw EmailCodeException(reason: EmailCodeFailure.invalidCode);
    }
    if (clock.now().isAfter(request.expiresAt)) {
      await EmailCodeRequest.db.deleteRow(session, request);
      throw EmailCodeException(reason: EmailCodeFailure.expired);
    }
    await EmailCodeRequest.db.updateRow(
      session,
      request.copyWith(consumedAt: clock.now()),
    );
    return issueFor(session, email, locale: request.locale);
  }

  /// A one-time sign-in link for a member, valid for [lifetime].
  static Future<SignInLinkCreated> createLink(
    Session session,
    String rawEmail, {
    Duration lifetime = const Duration(minutes: 30),
  }) async {
    final email = normalize(rawEmail);
    if (!_emailRe.hasMatch(email)) {
      throw EmailCodeException(reason: EmailCodeFailure.invalidEmail);
    }
    final token = Secrets.token(length: 40);
    final expires = clock.now().add(lifetime);
    await SignInLink.db.insertRow(
      session,
      SignInLink(
        email: email,
        tokenHash: Secrets.hash(token),
        expiresAt: expires,
      ),
    );
    return SignInLinkCreated(
      email: email,
      url: '${AppConfig.instance.publicUrl}/sign-in/link/$token',
      expiresAt: expires,
    );
  }

  /// Each link works once.
  Future<AuthSuccess> redeemLink(Session session, String token) async {
    final link = await SignInLink.db.findFirstRow(
      session,
      where: (t) => t.tokenHash.equals(Secrets.hash(token.trim())),
    );
    if (link == null || link.consumedAt != null) {
      throw EmailCodeException(reason: EmailCodeFailure.notFound);
    }
    if (clock.now().isAfter(link.expiresAt)) {
      throw EmailCodeException(reason: EmailCodeFailure.expired);
    }
    if (!await hasAccess(session, link.email)) {
      throw EmailCodeException(reason: EmailCodeFailure.noAccess);
    }
    await SignInLink.db.updateRow(
      session,
      link.copyWith(consumedAt: clock.now()),
    );
    return issueFor(session, link.email);
  }

  Future<AuthSuccess> issueFor(
    Session session,
    String email, {
    String locale = 'en',
  }) => session.db.transaction((tx) async {
    var account = await EmailCodeAccount.db.findFirstRow(
      session,
      where: (t) => t.email.equals(email),
      transaction: tx,
    );
    if (account == null) {
      final user = await _authUsers.create(session, transaction: tx);
      account = await EmailCodeAccount.db.insertRow(
        session,
        EmailCodeAccount(
          authUserId: user.id,
          email: email,
          locale: locale,
          lastLoginAt: clock.now(),
        ),
        transaction: tx,
      );
    } else {
      await EmailCodeAccount.db.updateRow(
        session,
        account.copyWith(lastLoginAt: clock.now()),
        transaction: tx,
      );
    }
    final user = await _authUsers.get(
      session,
      authUserId: account.authUserId,
      transaction: tx,
    );
    return _tokenManager.issueToken(
      session,
      authUserId: account.authUserId,
      method: method,
      scopes: user.scopes,
      transaction: tx,
    );
  });

  @override
  Future<void> mergeAuthUsers(
    Session session, {
    required UuidValue userToKeepId,
    required UuidValue userToRemoveId,
    required Transaction transaction,
  }) async {
    for (final r in await EmailCodeAccount.db.find(
      session,
      where: (t) => t.authUserId.equals(userToRemoveId),
      transaction: transaction,
    )) {
      await EmailCodeAccount.db.updateRow(
        session,
        r.copyWith(authUserId: userToKeepId),
        transaction: transaction,
      );
    }
  }
}

extension EmailCodeIdpGetter on AuthServices {
  EmailCodeIdp get emailCodeIdp =>
      AuthServices.getIdentityProvider<EmailCodeIdp>();
}
