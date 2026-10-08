// The test stage of a deploy.
//
// Suites run after the files are exported and before anything is built or
// uploaded (local runner), or in a throwaway container on the server from
// the uploaded files, before the images are built (container runner). A
// failed suite stops the deploy. Results go into the operation result, the
// history, and a per-commit record on the server that other environments
// read to decide whether a commit has passed its tests.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/events.dart';
import '../config/config.dart';
import '../remote/ssh.dart';
import 'context.dart';

/// A run that passed before with the same inputs as a suite has now.
class PriorPass {
  PriorPass({
    required this.sha,
    required this.env,
    required this.at,
    this.passed = 0,
  });

  factory PriorPass.fromJson(Map<String, Object?> j) => PriorPass(
    sha: '${j['sha']}',
    env: '${j['env']}',
    at: '${j['at']}',
    passed: (j['passed'] as num? ?? 0).toInt(),
  );

  final String sha;
  final String env;
  final String at;
  final int passed;
}

/// What the test stage knows before it runs: each suite's input hash, and
/// the suites whose inputs passed before (they are skipped).
class SuitePlan {
  SuitePlan({this.hashes = const {}, this.prior = const {}});

  /// Suite name → input hash (suites without a hash always run).
  final Map<String, String> hashes;

  /// Suite name → the earlier passing run with the same hash.
  final Map<String, PriorPass> prior;

  bool skips(TestSuite s) => prior.containsKey(s.name);
}

/// The result of a suite that did not run because nothing changed.
SuiteResult _unchanged(TestSuite s, SuitePlan plan) {
  final prior = plan.prior[s.name]!;
  return SuiteResult(
    suite: s.name,
    ok: true,
    duration: Duration.zero,
    passed: prior.passed,
    inputsHash: plan.hashes[s.name],
    sameAs: prior.sha,
  );
}

final _summary = RegExp(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: ');
final _failedTest = RegExp(r'^\d\d:\d\d \+\d+(?: ~\d+)? -\d+: (.*?) \[E\]\s*$');

/// Parses the counts and failed tests from `dart test` / `flutter test`
/// output (the compact or expanded reporter).
({int passed, int skipped, int failed, List<String> failures}) parseTestOutput(
  String output,
) {
  var passed = 0, skipped = 0, failed = 0;
  final failures = <String>{};
  for (final raw in const LineSplitter().convert(output)) {
    final line = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
    for (final m in _summary.allMatches(line)) {
      passed = int.parse(m[1]!);
      skipped = int.tryParse(m[2] ?? '') ?? 0;
      failed = int.tryParse(m[3] ?? '') ?? 0;
    }
    final f = _failedTest.firstMatch(line.trim());
    if (f != null) failures.add(f[1]!);
  }
  return (
    passed: passed,
    skipped: skipped,
    failed: failed,
    failures: failures.toList(),
  );
}

/// Runs [suites] on this machine in [root]. Emits suite events and writes
/// each suite's output to [logDir]. Never throws for a failing suite.
/// With [parallel], the suites run at the same time. Suites that [plan]
/// marks as unchanged do not run.
Future<List<SuiteResult>> runSuitesLocally(
  Ctx ctx,
  List<TestSuite> suites,
  String root,
  String logDir, {
  bool parallel = true,
  SuitePlan? plan,
}) async {
  Directory(logDir).createSync(recursive: true);
  final p0 = plan ?? SuitePlan();
  Future<SuiteResult> one(TestSuite s) async {
    if (p0.skips(s)) {
      final r = _unchanged(s, p0);
      ctx.log.emit(SuiteFinished(r));
      return r;
    }
    return _runLocally(ctx, s, root, logDir, p0.hashes[s.name]);
  }

  if (parallel) return Future.wait(suites.map(one));
  final out = <SuiteResult>[];
  for (final s in suites) {
    out.add(await one(s));
  }
  return out;
}

Future<SuiteResult> _runLocally(
  Ctx ctx,
  TestSuite s,
  String root,
  String logDir,
  String? hash,
) async {
  {
    ctx.log.emit(SuiteStarted(s.name, s.command));
    final watch = Stopwatch()..start();
    final logFile = File(p.join(logDir, '${s.name}.log'));
    final sink = logFile.openWrite();
    final buffer = StringBuffer();
    final proc = await Process.start('bash', [
      '-c',
      s.command,
    ], workingDirectory: p.join(root, s.dir));
    await proc.stdin.close();
    var timedOut = false;
    final timer = Timer(Duration(seconds: s.timeoutSeconds), () {
      timedOut = true;
      proc.kill(ProcessSignal.sigterm);
    });
    final seen = <String>{};
    void onLine(String l) {
      sink.writeln(l);
      buffer.writeln(l);
      final clean = l.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '').trim();
      final f = _failedTest.firstMatch(clean);
      if (f != null && seen.add(f[1]!)) ctx.log.emit(TestFailed(s.name, f[1]!));
      if (ctx.log.verbose) ctx.log.output(l);
    }

    await Future.wait([
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(onLine),
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(onLine),
    ]);
    final code = await proc.exitCode;
    timer.cancel();
    await sink.close();
    final parsed = parseTestOutput(buffer.toString());
    final r = SuiteResult(
      suite: s.name,
      ok: code == 0 && !timedOut,
      duration: watch.elapsed,
      passed: parsed.passed,
      skipped: parsed.skipped,
      failed: parsed.failed,
      failures: parsed.failures,
      exitCode: code,
      timedOut: timedOut,
      log: logFile.path,
      inputsHash: hash,
    );
    ctx.log.emit(SuiteFinished(r));
    return r;
  }
}

/// The script that runs one suite in a container on the server, from the
/// release files in [filesDir]. It prints the output, then
/// `PODSHIP_TEST_EXIT=<code>`.
String containerSuiteScript(TestSuite s, String filesDir) {
  final image = s.image ?? 'dart:stable';
  return '''
set +e
timeout ${s.timeoutSeconds} docker run --rm -v ${shq(filesDir)}:/w -w ${shq(p.posix.join('/w', s.dir))} ${shq(image)} bash -c ${shq(s.command)} 2>&1
echo "PODSHIP_TEST_EXIT=\$?"
''';
}

/// Runs [suites] in containers on [env]'s server. Suites that [plan]
/// marks as unchanged do not run.
Future<List<SuiteResult>> runSuitesInContainers(
  Ctx ctx,
  EnvConfig env,
  List<TestSuite> suites,
  String filesDir,
  String logDir, {
  bool parallel = true,
  SuitePlan? plan,
}) async {
  Directory(logDir).createSync(recursive: true);
  final p0 = plan ?? SuitePlan();
  Future<SuiteResult> one(TestSuite s) async {
    if (p0.skips(s)) {
      final r = _unchanged(s, p0);
      ctx.log.emit(SuiteFinished(r));
      return r;
    }
    return _runInContainer(ctx, env, s, filesDir, logDir, p0.hashes[s.name]);
  }

  if (parallel) return Future.wait(suites.map(one));
  final out = <SuiteResult>[];
  for (final s in suites) {
    out.add(await one(s));
  }
  return out;
}

Future<SuiteResult> _runInContainer(
  Ctx ctx,
  EnvConfig env,
  TestSuite s,
  String filesDir,
  String logDir,
  String? hash,
) async {
  {
    ctx.log.emit(
      SuiteStarted(
        s.name,
        '${s.command} (in ${s.image ?? 'dart:stable'} on ${env.host})',
      ),
    );
    final watch = Stopwatch()..start();
    final buffer = StringBuffer();
    var code = -1;
    final seen = <String>{};
    await ctx.ssh.lines(
      env.host,
      ctx.header(env) + containerSuiteScript(s, filesDir),
      (l, _) {
        final m = RegExp(r'^PODSHIP_TEST_EXIT=(\d+)$').firstMatch(l);
        if (m != null) {
          code = int.parse(m[1]!);
          return;
        }
        buffer.writeln(l);
        final f = _failedTest.firstMatch(
          l.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '').trim(),
        );
        if (f != null && seen.add(f[1]!)) {
          ctx.log.emit(TestFailed(s.name, f[1]!));
        }
      },
    );
    final logFile = File(p.join(logDir, '${s.name}.log'))
      ..writeAsStringSync(buffer.toString());
    final parsed = parseTestOutput(buffer.toString());
    final r = SuiteResult(
      suite: s.name,
      ok: code == 0,
      duration: watch.elapsed,
      passed: parsed.passed,
      skipped: parsed.skipped,
      failed: parsed.failed,
      failures: parsed.failures,
      exitCode: code,
      timedOut: code == 124,
      log: logFile.path,
      inputsHash: hash,
    );
    ctx.log.emit(SuiteFinished(r));
    return r;
  }
}

/// Where a commit's test record lives on a server.
String testRecordPath(EnvConfig env, String project, String sha) =>
    p.posix.join(env.podshipHome, 'history', project, 'tests', '$sha.json');

/// Where the record of a passing run with input hash [hash] lives:
/// `<podship_home>/history/<project>/tests/by-hash/<suite>-<hash>.json`.
String suiteHashPath(
  EnvConfig env,
  String project,
  String suite,
  String hash,
) => p.posix.join(
  env.podshipHome,
  'history',
  project,
  'tests',
  'by-hash',
  '$suite-$hash.json',
);

/// Finds, on the servers of the project, a passing run for each suite whose
/// current input hash is in [hashes]. One ssh call per distinct server.
Future<Map<String, PriorPass>> findPriorPasses(
  Ctx ctx,
  Map<String, String> hashes,
) async {
  final out = <String, PriorPass>{};
  if (hashes.isEmpty) return out;
  final seen = <String>{};
  for (final e in ctx.config.environments.values) {
    if (!seen.add('${e.host} ${e.podshipHome}')) continue;
    final script = StringBuffer();
    for (final h in hashes.entries) {
      if (out.containsKey(h.key)) continue;
      final path = suiteHashPath(e, ctx.config.project, h.key, h.value);
      script.writeln(
        'if [ -f ${shq(path)} ]; then printf \'%s\\t\' ${shq(h.key)}; tr -d \'\\n\' < ${shq(path)}; echo; fi',
      );
    }
    if (script.isEmpty) break;
    try {
      final text = await ctx.query(e, script.toString());
      for (final line in const LineSplitter().convert(text)) {
        final tab = line.indexOf('\t');
        if (tab < 1) continue;
        final suite = line.substring(0, tab);
        final j = jsonDecode(line.substring(tab + 1));
        if (j is Map<String, Object?> && j['ok'] == true) {
          out[suite] = PriorPass.fromJson(j);
        }
      }
    } catch (_) {
      // A server that does not answer only means no skip.
    }
  }
  return out;
}

/// Writes the test record of [sha] (and the suite logs) on [env]'s server.
/// Returns the record path.
Future<String> writeTestRecord(
  Ctx ctx,
  EnvConfig env,
  String sha,
  List<SuiteResult> results,
) async {
  final path = testRecordPath(env, ctx.config.project, sha);
  final dir = p.posix.dirname(path);
  final remote = <SuiteResult>[];
  for (final r in results) {
    final remoteLog = '$dir/$sha-${r.suite}.log';
    if (r.log != null && File(r.log!).existsSync()) {
      await ctx.query(
        env,
        'mkdir -p ${shq(dir)} && cat > ${shq(remoteLog)}',
        stdin: File(r.log!).readAsBytesSync(),
      );
    }
    remote.add(SuiteResult.fromJson({...r.toJson(), 'log': remoteLog}));
  }
  final record = {
    'sha': sha,
    'env': env.name,
    'ok': results.every((r) => r.ok),
    'at': DateTime.now().toUtc().toIso8601String(),
    'suites': [for (final r in remote) r.toJson()],
  };
  await ctx.query(
    env,
    'mkdir -p ${shq(dir)} && cat > ${shq(path)}',
    stdin: utf8.encode('${jsonEncode(record)}\n'),
  );
  // A passing suite with a hash lets the next deploy with the same inputs
  // skip it. A skipped suite keeps the record of the run it stands on.
  final byHash = StringBuffer();
  for (final r in remote) {
    final h = r.inputsHash;
    if (h == null || !r.ok || r.unchanged) continue;
    final hp = suiteHashPath(env, ctx.config.project, r.suite, h);
    final j = jsonEncode({
      'suite': r.suite,
      'hash': h,
      'sha': sha,
      'env': env.name,
      'at': record['at'],
      'ok': true,
      'passed': r.passed,
    });
    byHash.writeln(
      'mkdir -p ${shq(p.posix.dirname(hp))} && printf \'%s\\n\' ${shq(j)} > ${shq(hp)}',
    );
  }
  if (byHash.isNotEmpty) await ctx.query(env, byHash.toString());
  return path;
}

/// Finds a passing test record of [sha] on any environment's server.
/// Returns the environment name, or null.
Future<String?> findPassingTests(Ctx ctx, String sha) async {
  final seen = <String>{};
  for (final e in ctx.config.environments.values) {
    final key = '${e.host} ${e.podshipHome}';
    if (!seen.add(key)) continue;
    try {
      final out = await ctx.query(
        e,
        'cat ${shq(testRecordPath(e, ctx.config.project, sha))} 2>/dev/null || true',
      );
      if (out.trim().isEmpty) continue;
      final j = jsonDecode(out) as Map<String, Object?>;
      if (j['ok'] == true) return '${j['env']}';
    } catch (_) {}
  }
  return null;
}
