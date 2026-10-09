import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../integrations/integration_service.dart';
import '../workspace/workspace_service.dart';

/// The integrations page (spec INT). Every call needs a signed-in member;
/// connect and disconnect need an owner or admin (INT-3).
class IntegrationsEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  Future<List<IntegrationView>> list(Session session) async =>
      IntegrationService.list(session, await WorkspaceService.actorOf(session));

  /// The Cloudflare dashboard link with the permissions filled in (INT-8).
  Future<String> cloudflareTokenUrl(Session session) async {
    await WorkspaceService.actorOf(session);
    return IntegrationService.cloudflareTokenUrl();
  }

  Future<IntegrationView> saveCloudflare(Session session, String token) async =>
      IntegrationService.saveCloudflare(
        session,
        await WorkspaceService.actorOf(session),
        token,
      );

  Future<AwsStart> startAws(Session session) async =>
      IntegrationService.startAws(
        session,
        await WorkspaceService.actorOf(session),
      );

  Future<IntegrationView> disconnect(
    Session session,
    IntegrationProvider provider,
  ) async => IntegrationService.disconnect(
    session,
    await WorkspaceService.actorOf(session),
    provider,
  );

  Future<IntegrationView> check(
    Session session,
    IntegrationProvider provider,
  ) async => IntegrationService.check(
    session,
    await WorkspaceService.actorOf(session),
    provider,
  );
}
