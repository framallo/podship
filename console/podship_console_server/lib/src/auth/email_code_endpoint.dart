import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_idp_server/core.dart';

import 'email_code_idp.dart';

/// Sign in with an emailed code or a one-time link.
class EmailCodeEndpoint extends Endpoint {
  EmailCodeIdp get _idp => AuthServices.instance.emailCodeIdp;

  Future<void> requestCode(Session session, String email, String locale) =>
      _idp.requestCode(session, email, locale: locale);

  Future<AuthSuccess> verifyCode(Session session, String email, String code) =>
      _idp.verifyCode(session, email, code);

  /// Redeems `/sign-in/link/<token>`.
  Future<AuthSuccess> redeemLink(Session session, String token) =>
      _idp.redeemLink(session, token);
}
