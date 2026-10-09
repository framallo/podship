import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../workspace/workspace_service.dart';

class MeEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  Future<Me> get(Session session) async {
    final a = await WorkspaceService.actorOf(session);
    final account = await EmailCodeAccount.db.findFirstRow(
      session,
      where: (t) => t.email.equals(a.email),
    );
    return Me(
      email: a.email,
      workspaceId: a.workspace.id!,
      workspaceName: a.workspace.name,
      role: a.role,
      canManage: a.canManage,
      locale: account?.locale ?? 'en',
    );
  }
}
