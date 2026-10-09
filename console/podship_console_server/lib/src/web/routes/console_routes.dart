import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:serverpod/serverpod.dart';

import '../../auth/email_code_idp.dart';
import '../../core/secrets.dart';
import '../../generated/protocol.dart';
import '../../integrations/integration_service.dart';
import '../../integrations/oidc.dart';
import '../../workspace/workspace_service.dart';

/// A JSON response that no cache keeps.
///
/// Routes never answer 404: Serverpod passes a 404 on to the Flutter app
/// route, which answers 405 to a POST.
Response jsonResponse(Object? data, {int status = 200}) => Response(
  status,
  body: Body.fromString(jsonEncode(data), mimeType: MimeType.json),
  headers: Headers.build((h) {
    h['cache-control'] = ['no-store'];
  }),
);

Response errorResponse(int status, String code, String message) =>
    jsonResponse({'error': code, 'message': message}, status: status);

String? bearerOf(Request request) {
  final h = request.headers['authorization']?.firstOrNull;
  if (h == null) return null;
  return RegExp(
    r'^\s*Bearer\s+(\S+)\s*$',
    caseSensitive: false,
  ).firstMatch(h)?[1];
}

Future<Object?> _json(Request request) async {
  try {
    return jsonDecode(await request.readAsString());
  } on FormatException {
    return null;
  }
}

/// `GET /health`: 200 when the database answers, with the podship release.
class HealthRoute extends Route {
  @override
  Future<Result> handleCall(Session session, Request request) async {
    await Workspace.db.count(session);
    final env = Platform.environment;
    return jsonResponse({
      'ok': true,
      if ((env['PODSHIP_RELEASE'] ?? '').isNotEmpty)
        'release': env['PODSHIP_RELEASE'],
      if ((env['PODSHIP_COMMIT'] ?? '').isNotEmpty)
        'commit': env['PODSHIP_COMMIT'],
    });
  }
}

/// `GET /.well-known/openid-configuration`: AWS reads it (decision).
class OidcDiscoveryRoute extends Route {
  @override
  Future<Result> handleCall(Session session, Request request) async =>
      jsonResponse(Oidc.discovery());
}

/// `GET /.well-known/jwks.json`: the public signing key.
class JwksRoute extends Route {
  @override
  Future<Result> handleCall(Session session, Request request) async =>
      jsonResponse(await Oidc.jwks(session));
}

/// `POST /integrations/aws/callback`: the stack's Lambda (INT-12, INT-18).
/// A wrong or used code gets 403 and changes nothing.
class AwsCallbackRoute extends Route {
  AwsCallbackRoute() : super(methods: {Method.post});

  @override
  Future<Result> handleCall(Session session, Request request) async {
    final body = await _json(request);
    if (body is! Map) return errorResponse(400, 'invalid', 'JSON expected');
    final ok = await IntegrationService.awsCallback(
      session,
      body.cast<String, Object?>(),
    );
    return ok
        ? jsonResponse({'ok': true})
        : errorResponse(403, 'unknownCode', 'unknown or used code');
  }
}

/// The podship CLI's console API (protocol 1): `GET /podship/v1/whoami` and
/// `GET /podship/v1/integrations/{cloudflare|aws}/credentials` (INT-19), with a personal
/// access token.
class PodshipApiRoute extends Route {
  @override
  Future<Result> handleCall(Session session, Request request) async {
    final token = bearerOf(request);
    final actor = token == null
        ? null
        : await WorkspaceService.actorOfToken(session, token);
    if (actor == null) {
      return errorResponse(
        401,
        'unauthorized',
        'a personal access token is needed',
      );
    }
    final segs = request.url.pathSegments;
    final i = segs.indexOf('v1');
    final rest = i < 0 ? const <String>[] : segs.sublist(i + 1);
    if (rest.length == 1 && rest[0] == 'whoami') {
      return jsonResponse({
        'user': actor.email,
        'workspace': actor.workspace.slug,
        'roles': {actor.workspace.slug: actor.role.name},
      });
    }
    // `integrations/{provider}/credentials` (also `credentials/{provider}`).
    final name =
        rest.length == 3 &&
            rest[0] == 'integrations' &&
            rest[2] == 'credentials'
        ? rest[1]
        : rest.length == 2 && rest[0] == 'credentials'
        ? rest[1]
        : null;
    if (name != null) {
      final p = IntegrationProvider.values
          .where((v) => v.name == name)
          .firstOrNull;
      if (p == null)
        return errorResponse(400, 'unknownProvider', 'no such provider');
      try {
        return jsonResponse(
          await IntegrationService.credentialsFor(session, actor, p),
        );
      } on IntegrationException catch (e) {
        return e.reason == IntegrationFailure.forbidden
            ? errorResponse(403, 'forbidden', 'owners and admins only')
            : errorResponse(409, 'notConnected', '${p.name} is not connected');
      } on Object catch (e) {
        session.log('credentials ${p.name}: ${e.runtimeType}');
        return errorResponse(502, 'providerFailed', 'the provider refused');
      }
    }
    return errorResponse(400, 'unknownPath', 'unknown path');
  }
}

/// `/internal/...` with `X-Podship-Service: <serviceSecret>`. nginx does not
/// route `/internal/`: it is reached only from inside the container
/// (`podship_console_tool`).
abstract class InternalRoute extends Route {
  InternalRoute() : super(methods: {Method.post});

  Future<Result> handle(Session session, Map<String, Object?> body);

  @override
  Future<Result> handleCall(Session session, Request request) async {
    final secret = Serverpod.instance.getPassword('serviceSecret');
    final given = request.headers['x-podship-service']?.firstOrNull ?? '';
    if (secret == null || secret.isEmpty || !Secrets.equal(given, secret)) {
      return errorResponse(403, 'forbidden', 'forbidden');
    }
    final body = await _json(request);
    return handle(
      session,
      body is Map ? body.cast<String, Object?>() : const {},
    );
  }
}

/// `{"email"}` → a one-time sign-in link (30 minutes).
class InternalSignInLinkRoute extends InternalRoute {
  @override
  Future<Result> handle(Session session, Map<String, Object?> body) async {
    final email = EmailCodeIdp.normalize('${body['email'] ?? ''}');
    if (!await EmailCodeIdp.hasAccess(session, email)) {
      return errorResponse(403, 'noAccess', 'not a workspace member');
    }
    final link = await EmailCodeIdp.createLink(session, email);
    return jsonResponse({
      'email': link.email,
      'url': link.url,
      'expiresAt': link.expiresAt.toIso8601String(),
    });
  }
}

/// `{"email", "name", "days"}` → a personal access token for the podship
/// CLI, shown once.
class InternalAccessTokenRoute extends InternalRoute {
  @override
  Future<Result> handle(Session session, Map<String, Object?> body) async {
    final email = EmailCodeIdp.normalize('${body['email'] ?? ''}');
    final ws = await WorkspaceService.ensure(session);
    final role = await WorkspaceService.roleOf(session, ws, email);
    if (role == null) {
      return errorResponse(403, 'noAccess', 'not a workspace member');
    }
    final name = '${body['name'] ?? 'cli'}';
    final days = (body['days'] as num?)?.toInt() ?? 90;
    final token = Secrets.token(prefix: 'psc_', length: 40);
    await AccessToken.db.insertRow(
      session,
      AccessToken(
        workspaceId: ws.id!,
        email: email,
        name: name,
        tokenHash: IntegrationService.hashToken(token),
        expiresAt: clock.now().toUtc().add(Duration(days: days.clamp(1, 365))),
      ),
    );
    return jsonResponse({'email': email, 'name': name, 'token': token});
  }
}
