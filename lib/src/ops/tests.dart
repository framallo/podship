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
Future<List<SuiteResult>> runSuitesLocally(
  Ctx ctx,
  List<TestSuite> suites,
  String root,
  String logDir,
) async {
  final out = <SuiteResult>[];
  Directory(logDir).createSync(recursive: true);
  for (final s in suites) {
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
    );
    ctx.log.emit(SuiteFinished(r));
    out.add(r);
  }
  return out;
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

/// Runs [suites] in containers on [env]'s server.
Future<List<SuiteResult>> runSuitesInContainers(
  Ctx ctx,
  EnvConfig env,
  List<TestSuite> suites,
  String filesDir,
  String logDir,
) async {
  final out = <SuiteResult>[];
  Directory(logDir).createSync(recursive: true);
  for (final s in suites) {
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
    );
    ctx.log.emit(SuiteFinished(r));
    out.add(r);
  }
  return out;
}

/// Where a commit's test record lives on a server.
String testRecordPath(EnvConfig env, String project, String sha) =>
    p.posix.join(env.podshipHome, 'history', project, 'tests', '$sha.json');

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
