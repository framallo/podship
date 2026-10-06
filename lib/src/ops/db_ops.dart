// Database helpers shared by the library and the CLI.

import '../config/config.dart';
import '../remote/ssh.dart';
import 'context.dart';

/// The shell expression that finds the database container of [e].
String dbContainerExpr(EnvConfig e) => e.database.mode == DatabaseMode.shared
    ? DatabaseConfig.sharedContainer
    : '\$(docker ps -q --filter label=com.docker.compose.project=${shq(e.composeProject)} '
          '--filter label=com.docker.compose.service=${shq(e.database.service)} | head -1)';

/// The database admin role of [e].
String dbAdmin(EnvConfig e) =>
    e.database.mode == DatabaseMode.shared ? 'postgres' : e.database.user;

/// Runs SQL as the database admin and returns the output (`a | b` rows).
Future<String> sql(
  Ctx ctx,
  EnvConfig e,
  String query, {
  String? db,
}) => ctx.query(
  e,
  'c=${dbContainerExpr(e)}; [ -n "\$c" ] || { echo "no database container" >&2; exit 1; }\n'
  'docker exec -i "\$c" psql -U ${shq(dbAdmin(e))} -d ${shq(db ?? e.database.name)} -v ON_ERROR_STOP=1 -Atq -F " | "',
  stdin: query.codeUnits,
);
