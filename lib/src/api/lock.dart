// The environment lock: one mutating operation at a time per environment.
//
// The lock is the folder `<env dir>/.podship/lock`, created with `mkdir`
// (atomic, and portable: no flock on macOS). It holds `owner.json` with
// who, what and when. Every client takes it the same way, the CLI over
// ssh as well as a console, so two deploys never overlap.

import 'dart:convert';

import '../config/config.dart';
import '../ops/context.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';

/// The lock folder of [env].
String lockPath(EnvConfig env) => '${EnvLayout(env).state}/lock';

/// A lock older than this is reported as stale; `podship unlock` removes it.
const staleLockAge = Duration(hours: 6);

/// Takes the lock or throws [Aborted] naming its holder.
Future<void> acquireLock(
  Ctx ctx,
  EnvConfig env, {
  required String operation,
  required String actor,
}) async {
  final owner = jsonEncode({
    'operation': operation,
    'actor': actor,
    'started_at': DateTime.now().toUtc().toIso8601String(),
  });
  final l = lockPath(env);
  final out = await ctx.query(env, '''
mkdir -p ${shq(EnvLayout(env).state)}
if mkdir ${shq(l)} 2>/dev/null; then
  cat > ${shq('$l/owner.json')}
  echo LOCKED
else
  echo "HELD \$(cat ${shq('$l/owner.json')} 2>/dev/null | tr -d '\\n')"
fi
''', stdin: utf8.encode(owner));
  if (out.trim() == 'LOCKED') return;
  final held = out.trim().replaceFirst('HELD ', '');
  var who = held;
  try {
    final j = jsonDecode(held) as Map<String, Object?>;
    final since = DateTime.tryParse('${j['started_at']}');
    final stale =
        since != null &&
        DateTime.now().toUtc().difference(since) > staleLockAge;
    who =
        '${j['actor']} (${j['operation']}, since ${j['started_at']})${stale ? ' — stale; remove it with `podship unlock --env ${env.name}`' : ''}';
  } catch (_) {}
  throw Aborted('${env.name} is locked by $who');
}

/// Releases the lock (only when [mine] is true, so a failed acquire never
/// removes someone else's lock).
Future<void> releaseLock(Ctx ctx, EnvConfig env) =>
    ctx.query(env, 'rm -rf ${shq(lockPath(env))}');

/// The lock holder, or null.
Future<Map<String, Object?>?> readLock(Ctx ctx, EnvConfig env) async {
  final out = await ctx.query(
    env,
    'cat ${shq('${lockPath(env)}/owner.json')} 2>/dev/null || true',
  );
  if (out.trim().isEmpty) return null;
  try {
    return jsonDecode(out) as Map<String, Object?>;
  } catch (_) {
    return {'raw': out.trim()};
  }
}
