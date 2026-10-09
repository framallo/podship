import 'dart:io';

import 'package:serverpod/serverpod.dart';

import 'console_routes.dart';

/// `GET /assets/assets/config.json`: where the web app finds the API.
/// `CONSOLE_API_URL` (behind nginx: `https://<host>/rpc/`), else the
/// Serverpod API server.
class AppConfigRoute extends Route {
  AppConfigRoute(this.apiConfig);
  final ServerConfig apiConfig;

  @override
  Future<Result> handleCall(Session session, Request request) async {
    final env = Platform.environment['CONSOLE_API_URL'];
    final api =
        env ??
        Uri(
          scheme: apiConfig.publicScheme,
          host: apiConfig.publicHost,
          port: apiConfig.publicPort,
        ).toString();
    return jsonResponse({'apiUrl': api});
  }
}
