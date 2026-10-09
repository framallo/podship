import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_idp_server/core.dart';

import '../core/app_config.dart';
import '../generated/protocol.dart';
import '../integrations/integration_service.dart';

/// The signed-in person and their workspace role.
class Actor {
  Actor({
    required this.email,
    required this.workspace,
    required this.role,
    this.tokenName,
  });
  final String email;
  final Workspace workspace;
  final WorkspaceRole role;

  /// Set when a personal access token made the call (the CLI).
  final String? tokenName;

  /// Owners and admins connect and disconnect (INT-3).
  bool get canManage =>
      role == WorkspaceRole.owner || role == WorkspaceRole.admin;

  /// Who did it, for the audit (INT-7).
  String get label => tokenName == null ? email : '$email (token $tokenName)';
}

/// Phase 1 has one workspace, named by `CONSOLE_WORKSPACE`. The people in
/// `CONSOLE_OWNER_EMAILS` are its owners.
class WorkspaceService {
  static String slugOf(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// The workspace, made on first use, with the config owners as members.
  static Future<Workspace> ensure(Session session) async {
    final cfg = AppConfig.instance;
    final slug = slugOf(cfg.workspaceName);
    var ws = await Workspace.db.findFirstRow(
      session,
      where: (t) => t.slug.equals(slug),
    );
    ws ??= await Workspace.db.insertRow(
      session,
      Workspace(name: cfg.workspaceName, slug: slug),
    );
    for (final email in cfg.ownerEmails) {
      final m = await WorkspaceMember.db.findFirstRow(
        session,
        where: (t) => t.workspaceId.equals(ws!.id!) & t.email.equals(email),
      );
      if (m == null) {
        await WorkspaceMember.db.insertRow(
          session,
          WorkspaceMember(
            workspaceId: ws.id!,
            email: email,
            role: WorkspaceRole.owner,
          ),
        );
      } else if (m.role != WorkspaceRole.owner) {
        await WorkspaceMember.db.updateRow(
          session,
          m.copyWith(role: WorkspaceRole.owner),
        );
      }
    }
    return ws;
  }

  /// The role of [email], or null when the person is not a member.
  static Future<WorkspaceRole?> roleOf(
    Session session,
    Workspace ws,
    String email,
  ) async {
    if (AppConfig.instance.ownerEmails.contains(email)) {
      return WorkspaceRole.owner;
    }
    final m = await WorkspaceMember.db.findFirstRow(
      session,
      where: (t) => t.workspaceId.equals(ws.id!) & t.email.equals(email),
    );
    return m?.role;
  }

  /// The actor of a signed-in session. Throws [IntegrationException] with
  /// `forbidden` when the person is not a member.
  static Future<Actor> actorOf(Session session) async {
    final id = session.authenticated?.authUserId;
    if (id == null) {
      throw IntegrationException(reason: IntegrationFailure.forbidden);
    }
    final account = await EmailCodeAccount.db.findFirstRow(
      session,
      where: (t) => t.authUserId.equals(id),
    );
    if (account == null) {
      throw IntegrationException(reason: IntegrationFailure.forbidden);
    }
    final ws = await ensure(session);
    final role = await roleOf(session, ws, account.email);
    if (role == null) {
      throw IntegrationException(reason: IntegrationFailure.forbidden);
    }
    return Actor(email: account.email, workspace: ws, role: role);
  }

  /// The actor of a personal access token (`Authorization: Bearer psc_…`),
  /// or null.
  static Future<Actor?> actorOfToken(Session session, String token) async {
    final row = await AccessToken.db.findFirstRow(
      session,
      where: (t) => t.tokenHash.equals(IntegrationService.hashToken(token)),
    );
    final now = DateTime.now().toUtc();
    if (row == null || row.revokedAt != null || row.expiresAt.isBefore(now)) {
      return null;
    }
    final ws = await Workspace.db.findById(session, row.workspaceId);
    if (ws == null) return null;
    final role = await roleOf(session, ws, row.email);
    if (role == null) return null;
    await AccessToken.db.updateRow(session, row.copyWith(lastUsedAt: now));
    return Actor(
      email: row.email,
      workspace: ws,
      role: role,
      tokenName: row.name,
    );
  }
}
