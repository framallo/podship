// History records: one per operation, kept on the server.
//
//   <podship_home>/history/<project>/<env>/<stamp>-<operation>.json
//   <podship_home>/history/<project>/<env>/<stamp>-<operation>.log
//
// The JSON has who, when, the operation, the releases, the duration, the
// outcome and the log path. The log is the operation's event text. Neither
// holds secret values.

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../ops/context.dart';
import '../remote/ssh.dart';
import 'events.dart';

class HistoryRecord {
  HistoryRecord(this.json);
  final Map<String, Object?> json;

  String get operation => '${json['operation']}';
  String get project => '${json['project']}';
  String get env => '${json['env']}';
  String get startedAt => '${json['started_at']}';
  bool get ok => json['ok'] == true;
  String? get release => json['release'] as String?;
  String? get logPath => json['log'] as String?;
  Map<String, Object?> toJson() => json;
}

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}

/// Writes the record of [r] and its [transcript]. Returns the JSON path.
Future<String> writeHistory(
  Ctx ctx,
  EnvConfig env,
  OperationResult r,
  String actor,
  String transcript,
  Set<String> sensitive,
) async {
  final ended = DateTime.now().toUtc();
  final started = ended.subtract(r.duration);
  final dir = p.posix.join(
    env.podshipHome,
    'history',
    ctx.config.project,
    env.name,
  );
  final base = '${_stamp(started)}-${r.operation.replaceAll(' ', '-')}';
  final json = {
    ...r.toJson(),
    'data': {
      for (final e in r.data.entries)
        if (!sensitive.contains(e.key)) e.key: e.value,
    },
    'actor': actor,
    'started_at': started.toIso8601String(),
    'ended_at': ended.toIso8601String(),
    'log': '$dir/$base.log',
  }..remove('history');
  final path = '$dir/$base';
  await ctx.query(
    env,
    'mkdir -p ${shq(dir)} && cat > ${shq('$path.json')}',
    stdin: utf8.encode('${jsonEncode(json)}\n'),
  );
  await ctx.query(
    env,
    'cat > ${shq('$path.log')}',
    stdin: utf8.encode(transcript),
  );
  return '$dir/$base.json';
}

/// Reads the newest [limit] records of [env] (or of every project on its
/// server), oldest first.
Future<List<HistoryRecord>> readHistory(
  Ctx ctx,
  EnvConfig env,
  String project, {
  int limit = 20,
  bool allProjects = false,
}) async {
  final root = p.posix.join(env.podshipHome, 'history');
  final dir = allProjects ? root : p.posix.join(root, project, env.name);
  final out = await ctx.query(env, '''
[ -d ${shq(dir)} ] || exit 0
find ${shq(dir)} -name '*.json' -type f | awk -F/ '{print \$NF "\\t" \$0}' | sort | tail -n $limit | cut -f2 |
while read -r f; do tr -d '\\n' < "\$f"; echo; done
''');
  return [
    for (final line in const LineSplitter().convert(out))
      if (line.trim().isNotEmpty)
        if (jsonDecode(line) case final Map<String, Object?> m)
          HistoryRecord(m),
  ];
}
