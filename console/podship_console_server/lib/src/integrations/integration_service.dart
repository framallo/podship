import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:podship/podship.dart'
    show
        AwsCredentials,
        CloudflareApi,
        CloudflareException,
        HttpCall,
        HttpTransport,
        IoTransport,
        SesApi;
import 'package:serverpod/serverpod.dart';

import '../core/app_config.dart';
import '../core/secrets.dart';
import '../generated/protocol.dart';
import '../workspace/workspace_service.dart';
import 'aws_template.dart';
import 'oidc.dart';
import 'sts.dart';

/// The outside world, replaceable in tests.
class IntegrationDeps {
  IntegrationDeps({HttpTransport? transport})
    : transport = transport ?? IoTransport();
  final HttpTransport transport;
}

/// Workspace integrations (spec INT). Every credential is encrypted before
/// it reaches the database (INT-4) and never leaves the server for the
/// browser (INT-5) or a log (INT-6).
class IntegrationService {
  static IntegrationDeps deps = IntegrationDeps();

  /// The Cloudflare dashboard page that creates the token with the five
  /// permissions filled in (decision, checked 2026-10-09).
  static String cloudflareTokenUrl() {
    final perms = jsonEncode([
      {'key': 'zone', 'type': 'read'},
      {'key': 'dns', 'type': 'edit'},
      {'key': 'argotunnel', 'type': 'edit'},
      {'key': 'access', 'type': 'edit'},
      {'key': 'ssl_and_certificates', 'type': 'read'},
    ]);
    return 'https://dash.cloudflare.com/profile/api-tokens'
        '?permissionGroupKeys=${Uri.encodeQueryComponent(perms)}'
        '&accountId=*&zoneId=all'
        '&name=${Uri.encodeQueryComponent('podship console')}';
  }

  static String hashToken(String token) => Secrets.hash(token.trim());

  static String _aad(int workspaceId, IntegrationProvider p) =>
      'integration:$workspaceId:${p.name}';

  static Future<void> audit(
    Session session,
    Actor? actor,
    int workspaceId,
    IntegrationProvider provider,
    String action, {
    required bool ok,
    String detail = '',
    String? actorLabel,
  }) => IntegrationAudit.db.insertRow(
    session,
    IntegrationAudit(
      workspaceId: workspaceId,
      provider: provider,
      action: action,
      actor: actorLabel ?? actor?.label ?? 'system',
      ok: ok,
      detail: detail,
    ),
  );

  static void _needManage(Actor actor) {
    if (!actor.canManage) {
      throw IntegrationException(reason: IntegrationFailure.forbidden);
    }
  }

  static Future<Integration?> _row(
    Session session,
    int workspaceId,
    IntegrationProvider p,
  ) => Integration.db.findFirstRow(
    session,
    where: (t) => t.workspaceId.equals(workspaceId) & t.provider.equals(p),
  );

  static Map<String, Object?> _details(Integration? i) =>
      i == null ? {} : (jsonDecode(i.details) as Map).cast<String, Object?>();

  // --- Views -----------------------------------------------------------------

  static IntegrationView view(IntegrationProvider p, Integration? i) {
    final d = _details(i);
    return IntegrationView(
      provider: p,
      status: i?.status ?? 'off',
      hint: i?.hint,
      account: d['account'] as String?,
      zones: (d['zones'] as num?)?.toInt(),
      role: d['roleName'] as String?,
      sesRegion: d['sesRegion'] as String?,
      sesProduction: d['sesProduction'] as bool?,
      connectedBy: i?.connectedBy,
      connectedAt: i?.connectedAt,
      pendingSince: i?.status == 'pending' ? i?.updatedAt : null,
      lastCheckAt: i?.lastCheckAt,
      lastCheckOk: i?.lastCheckOk,
      lastError: i?.lastError,
    );
  }

  static Future<List<IntegrationView>> list(
    Session session,
    Actor actor,
  ) async {
    final rows = await Integration.db.find(
      session,
      where: (t) => t.workspaceId.equals(actor.workspace.id!),
    );
    return [
      for (final p in IntegrationProvider.values)
        view(p, rows.where((r) => r.provider == p).firstOrNull),
    ];
  }

  // --- Cloudflare ------------------------------------------------------------

  /// Checks [token] and returns the facts to show (INT-9). Throws
  /// [IntegrationException] naming the cause.
  static Future<Map<String, Object?>> checkCloudflare(String token) async {
    final api = CloudflareApi(token, transport: deps.transport);
    try {
      final status = await api.verifyToken();
      if (status != 'active') {
        throw IntegrationException(reason: IntegrationFailure.inactive);
      }
    } on CloudflareException catch (e) {
      throw IntegrationException(
        reason: e.status == 401 || e.status == 400 || e.status == 403
            ? IntegrationFailure.invalid
            : IntegrationFailure.unreachable,
      );
    }
    Future<T> need<T>(String permission, Future<T> Function() f) async {
      try {
        return await f();
      } on CloudflareException catch (e) {
        if (e.status == 401 || e.status == 403 || e.codes.contains(10000)) {
          throw IntegrationException(
            reason: IntegrationFailure.missingPermission,
            detail: permission,
          );
        }
        throw IntegrationException(reason: IntegrationFailure.unreachable);
      }
    }

    final zones = await need('zone:read', () => api.zones());
    if (zones.isEmpty) {
      throw IntegrationException(
        reason: IntegrationFailure.missingPermission,
        detail: 'zone:read',
      );
    }
    final accountId = zones.first.accountId;
    await need('dns:edit', () => api.dnsRecords(zones.first.id));
    await need('argotunnel:edit', () => api.tunnels(accountId));
    await need('access:edit', () => api.accessApps(accountId));
    var account = accountId;
    try {
      final r = await deps.transport.send(
        HttpCall(
          'GET',
          Uri.parse('https://api.cloudflare.com/client/v4/accounts/$accountId'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final name = ((r.json as Map?)?['result'] as Map?)?['name'];
      if (name is String && name.isNotEmpty) account = name;
    } on Object {
      // The name is only for the UI.
    }
    return {
      'account': account,
      'accountId': accountId,
      'zones': zones.length,
    };
  }

  static Future<IntegrationView> saveCloudflare(
    Session session,
    Actor actor,
    String rawToken,
  ) async {
    _needManage(actor);
    final ws = actor.workspace.id!;
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw IntegrationException(reason: IntegrationFailure.empty);
    }
    Map<String, Object?> facts;
    try {
      facts = await checkCloudflare(token);
    } on IntegrationException catch (e) {
      await audit(
        session,
        actor,
        ws,
        IntegrationProvider.cloudflare,
        'connect_refused',
        ok: false,
        detail: '${e.reason.name}${e.detail == null ? '' : ' ${e.detail}'}',
      );
      rethrow;
    }
    final now = clock.now().toUtc();
    final secret = await AppConfig.instance.vault.encrypt(
      token,
      aad: _aad(ws, IntegrationProvider.cloudflare),
    );
    final existing = await _row(session, ws, IntegrationProvider.cloudflare);
    final row = Integration(
      id: existing?.id,
      workspaceId: ws,
      provider: IntegrationProvider.cloudflare,
      status: 'connected',
      secret: secret,
      hint: Secrets.hint(token),
      details: jsonEncode(facts),
      connectedBy: actor.email,
      connectedAt: now,
      lastCheckAt: now,
      lastCheckOk: true,
      updatedAt: now,
    );
    final saved = existing == null
        ? await Integration.db.insertRow(session, row)
        : await Integration.db.updateRow(session, row);
    await audit(
      session,
      actor,
      ws,
      IntegrationProvider.cloudflare,
      'connect',
      ok: true,
      detail: 'account ${facts['accountId']}, ${facts['zones']} zones',
    );
    return view(IntegrationProvider.cloudflare, saved);
  }

  // --- AWS -------------------------------------------------------------------

  static Future<AwsStart> startAws(Session session, Actor actor) async {
    _needManage(actor);
    final cfg = AppConfig.instance;
    final ws = actor.workspace;
    final code = Secrets.token(length: 40);
    await AwsConnectRequest.db.insertRow(
      session,
      AwsConnectRequest(
        workspaceId: ws.id!,
        codeHash: Secrets.hash(code),
        createdBy: actor.email,
        expiresAt: clock.now().toUtc().add(const Duration(hours: 24)),
      ),
    );
    // Publish the signing key before AWS asks for it.
    await Oidc.activeKey(session);
    final now = clock.now().toUtc();
    final existing = await _row(session, ws.id!, IntegrationProvider.aws);
    if (existing == null) {
      await Integration.db.insertRow(
        session,
        Integration(
          workspaceId: ws.id!,
          provider: IntegrationProvider.aws,
          status: 'pending',
          updatedAt: now,
        ),
      );
    } else if (existing.status != 'connected') {
      await Integration.db.updateRow(
        session,
        existing.copyWith(status: 'pending', updatedAt: now, lastError: null),
      );
    }
    await audit(
      session,
      actor,
      ws.id!,
      IntegrationProvider.aws,
      'aws_template',
      ok: true,
    );
    return AwsStart(
      fileName: 'podship-aws-${ws.slug}.json',
      template: AwsTemplate.build(
        issuerUrl: cfg.publicUrl,
        subject: Oidc.subjectOf(ws),
        callbackUrl: '${cfg.publicUrl}/integrations/aws/callback',
        code: code,
        workspace: ws.name,
      ),
      consoleUrl: AwsTemplate.consoleUrl(cfg.sesRegion),
    );
  }

  /// Temporary credentials for [ws] (INT-19), or throws.
  /// The session policy of send-only credentials (the watch, sign-in
  /// codes): the role's rights cut down to sending email.
  static final sendOnlyPolicy = jsonEncode({
    'Version': '2012-10-17',
    'Statement': [
      {
        'Effect': 'Allow',
        'Action': ['ses:SendEmail', 'ses:SendRawEmail'],
        'Resource': '*',
      },
    ],
  });

  static Future<StsCredentials> assumeAws(
    Session session,
    Workspace ws, {
    String? roleArn,
    bool sendOnly = false,
  }) async {
    var arn = roleArn;
    if (arn == null) {
      final row = await _row(session, ws.id!, IntegrationProvider.aws);
      if (row == null || row.status != 'connected' || row.secret == null) {
        throw IntegrationException(reason: IntegrationFailure.empty);
      }
      arn = await AppConfig.instance.vault.decrypt(
        row.secret!,
        aad: _aad(ws.id!, IntegrationProvider.aws),
      );
    }
    final token = await Oidc.sign(session, Oidc.subjectOf(ws));
    return Sts(
      transport: deps.transport,
      region: AppConfig.instance.sesRegion,
    ).assumeRoleWithWebIdentity(
      roleArn: arn,
      token: token,
      sessionName: 'podship-console-${ws.slug}',
      sessionPolicy: sendOnly ? sendOnlyPolicy : null,
    );
  }

  /// The stack's callback (INT-12, INT-13, INT-18). Answers true when the
  /// code is known. The check of the role runs after the answer.
  static Future<bool> awsCallback(
    Session session,
    Map<String, Object?> body,
  ) async {
    final code = '${body['code'] ?? ''}';
    if (code.isEmpty) return false;
    final req = await AwsConnectRequest.db.findFirstRow(
      session,
      where: (t) => t.codeHash.equals(Secrets.hash(code)),
    );
    if (req == null) return false;
    final ws = await Workspace.db.findById(session, req.workspaceId);
    if (ws == null) return false;
    final type = '${body['request_type'] ?? ''}';
    final stackId = '${body['stack_id'] ?? ''}';
    final row = await _row(session, ws.id!, IntegrationProvider.aws);

    if (type == 'Delete') {
      final d = _details(row);
      if (row != null && (d['stackId'] == null || d['stackId'] == stackId)) {
        await _forgetAws(session, row);
        await audit(
          session,
          null,
          ws.id!,
          IntegrationProvider.aws,
          'aws_stack_deleted',
          ok: true,
          actorLabel: 'aws',
          detail: stackId,
        );
      }
      return true;
    }
    if (type != 'Create' && type != 'Update') return true;
    if (req.usedAt != null || req.expiresAt.isBefore(clock.now().toUtc())) {
      return false;
    }
    final roleArn = '${body['role_arn'] ?? ''}';
    final accountId = '${body['account_id'] ?? ''}';
    if (!RegExp(r'^arn:aws[a-z-]*:iam::\d{12}:role/').hasMatch(roleArn)) {
      return false;
    }
    await AwsConnectRequest.db.updateRow(
      session,
      req.copyWith(usedAt: clock.now().toUtc()),
    );
    await audit(
      session,
      null,
      ws.id!,
      IntegrationProvider.aws,
      'aws_callback',
      ok: true,
      actorLabel: 'aws',
      detail: 'account $accountId, stack $stackId',
    );
    // IAM takes a few seconds to know the new role: check after the answer.
    final createdBy = req.createdBy;
    unawaited(
      Future(() async {
        final s = await Serverpod.instance.createSession(enableLogging: false);
        try {
          await _finishAws(s, ws, roleArn, accountId, stackId, createdBy);
        } finally {
          await s.close();
        }
      }),
    );
    return true;
  }

  static Future<void> _finishAws(
    Session session,
    Workspace ws,
    String roleArn,
    String accountId,
    String stackId,
    String createdBy,
  ) async {
    Object? last;
    for (var i = 0; i < 24; i++) {
      try {
        final sts = await assumeAws(session, ws, roleArn: roleArn);
        final region = AppConfig.instance.sesRegion;
        final account = await SesApi(
          sts.credentials,
          region: region,
          transport: deps.transport,
        ).account();
        final now = clock.now().toUtc();
        final row = await _row(session, ws.id!, IntegrationProvider.aws);
        final data = Integration(
          id: row?.id,
          workspaceId: ws.id!,
          provider: IntegrationProvider.aws,
          status: 'connected',
          secret: await AppConfig.instance.vault.encrypt(
            roleArn,
            aad: _aad(ws.id!, IntegrationProvider.aws),
          ),
          hint: accountId.length > 4
              ? accountId.substring(accountId.length - 4)
              : null,
          details: jsonEncode({
            'account': accountId,
            'roleName': roleArn.split('/').last,
            'stackId': stackId,
            'sesRegion': region,
            'sesProduction': account.production,
          }),
          connectedBy: createdBy,
          connectedAt: now,
          lastCheckAt: now,
          lastCheckOk: true,
          updatedAt: now,
        );
        if (row == null) {
          await Integration.db.insertRow(session, data);
        } else {
          await Integration.db.updateRow(session, data);
        }
        await audit(
          session,
          null,
          ws.id!,
          IntegrationProvider.aws,
          'connect',
          ok: true,
          actorLabel: createdBy,
          detail: 'account $accountId, role ${roleArn.split('/').last}',
        );
        return;
      } on Object catch (e) {
        last = e;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    final row = await _row(session, ws.id!, IntegrationProvider.aws);
    if (row != null) {
      await Integration.db.updateRow(
        session,
        row.copyWith(lastError: _safe(last), updatedAt: clock.now().toUtc()),
      );
    }
    await audit(
      session,
      null,
      ws.id!,
      IntegrationProvider.aws,
      'connect_refused',
      ok: false,
      actorLabel: createdBy,
      detail: _safe(last),
    );
  }

  /// An error text without secrets: STS and SES errors carry codes, not
  /// tokens.
  static String _safe(Object? e) {
    if (e is StsError) return '${e.code}: ${e.message}';
    if (e is IntegrationException) return e.reason.name;
    final t = '$e';
    return t.length > 200 ? t.substring(0, 200) : t;
  }

  static Future<void> _forgetAws(Session session, Integration row) async {
    await Integration.db.deleteRow(session, row);
    await Oidc.rotate(session);
  }

  // --- Disconnect, check, credentials -----------------------------------------

  static Future<IntegrationView> disconnect(
    Session session,
    Actor actor,
    IntegrationProvider p,
  ) async {
    _needManage(actor);
    final ws = actor.workspace.id!;
    final row = await _row(session, ws, p);
    if (row != null) {
      if (p == IntegrationProvider.aws) {
        await _forgetAws(session, row);
      } else {
        await Integration.db.deleteRow(session, row);
      }
    }
    await audit(session, actor, ws, p, 'disconnect', ok: true);
    return view(p, null);
  }

  /// Checks a connected integration again and records the result.
  static Future<IntegrationView> check(
    Session session,
    Actor actor,
    IntegrationProvider p,
  ) async {
    final ws = actor.workspace;
    final row = await _row(session, ws.id!, p);
    if (row == null || row.status != 'connected') return view(p, row);
    final now = clock.now().toUtc();
    try {
      if (p == IntegrationProvider.cloudflare) {
        await checkCloudflare(await _secret(session, row));
      } else {
        final sts = await assumeAws(session, ws);
        await SesApi(
          sts.credentials,
          region: AppConfig.instance.sesRegion,
          transport: deps.transport,
        ).account();
      }
      final saved = await Integration.db.updateRow(
        session,
        row.copyWith(lastCheckAt: now, lastCheckOk: true, lastError: null),
      );
      return view(p, saved);
    } on Object catch (e) {
      final saved = await Integration.db.updateRow(
        session,
        row.copyWith(lastCheckAt: now, lastCheckOk: false, lastError: _safe(e)),
      );
      await audit(
        session,
        actor,
        ws.id!,
        p,
        'check_failed',
        ok: false,
        detail: _safe(e),
      );
      return view(p, saved);
    }
  }

  static Future<String> _secret(Session session, Integration row) =>
      AppConfig.instance.vault.decrypt(
        row.secret!,
        aad: _aad(row.workspaceId, row.provider),
      );

  /// For the podship CLI and the watch (INT-19): the Cloudflare token, or
  /// AWS credentials for 1 hour, in the JSON that podship's secret store
  /// uses. AWS credentials are send-only ([sendOnlyPolicy]) unless [full]
  /// (`?scope=full`: `email setup`, `email sender`).
  static Future<Map<String, Object?>> credentialsFor(
    Session session,
    Actor actor,
    IntegrationProvider p, {
    bool full = false,
  }) async {
    _needManage(actor);
    final ws = actor.workspace;
    final row = await _row(session, ws.id!, p);
    if (row == null || row.status != 'connected' || row.secret == null) {
      await audit(
        session,
        actor,
        ws.id!,
        p,
        'credential_read',
        ok: false,
        detail: 'not connected',
      );
      throw IntegrationException(reason: IntegrationFailure.empty);
    }
    if (p == IntegrationProvider.cloudflare) {
      final token = await _secret(session, row);
      await audit(session, actor, ws.id!, p, 'credential_read', ok: true);
      return {'provider': 'cloudflare', 'token': token};
    }
    final sts = await assumeAws(session, ws, sendOnly: !full);
    await audit(
      session,
      actor,
      ws.id!,
      p,
      'credential_read',
      ok: true,
      detail:
          '${full ? 'full' : 'send-only'} sts until '
          '${sts.expiration.toIso8601String()}',
    );
    final AwsCredentials c = sts.credentials;
    return {
      'provider': 'aws',
      'access_key_id': c.accessKeyId,
      'secret_access_key': c.secretAccessKey,
      'session_token': c.sessionToken,
      'expiration': sts.expiration.toIso8601String(),
      'region': AppConfig.instance.sesRegion,
      'scope': full ? 'full' : 'send',
    };
  }
}
