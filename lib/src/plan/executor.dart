import 'dart:convert';
// Runs plans and reports what happens as events.

import 'dart:io';

import '../api/events.dart';
import '../remote/ssh.dart';
import '../util/log.dart';
import '../config/config.dart';
import 'plan.dart';

/// Runs the steps of a [Plan] in order.
class Executor {
  Executor(this.ssh, this.log);
  final Ssh ssh;
  final Log log;

  void _line(String l, bool err) => log.output(l, stderr: err);

  /// Runs [p]. On a failure in a guarded step, runs the recovery steps,
  /// then throws the first failure.
  Future<void> run(Plan p) async {
    final watch = Stopwatch()..start();
    final total = p.steps.length;
    for (final (i, step) in p.steps.indexed) {
      final t0 = watch.elapsed;
      log.emit(StepStarted(i + 1, total, step.title));
      try {
        await runStep(step);
      } catch (e) {
        log.emit(StepFailed(i + 1, step.title, '$e'));
        if (p.guards(i) && p.recovery.isNotEmpty) {
          log.warn('Recovering');
          for (final (j, r) in p.recovery.indexed) {
            log.emit(
              StepStarted(j + 1, p.recovery.length, r.title, recovery: true),
            );
            final r0 = watch.elapsed;
            try {
              await runStep(r);
              log.emit(StepFinished(j + 1, r.title, watch.elapsed - r0));
            } catch (e2) {
              log.emit(StepFailed(j + 1, r.title, '$e2'));
            }
          }
        }
        rethrow;
      }
      log.emit(StepFinished(i + 1, step.title, watch.elapsed - t0));
    }
  }

  Future<void> runStep(Step step) async {
    switch (step) {
      case LocalStep():
        final code = await runLines(
          step.command.first,
          step.command.sublist(1),
          _line,
          workingDirectory: step.cwd,
          environment: step.env.isEmpty ? null : step.env,
        );
        if (code != 0) throw StepError(step, 'exit code $code');
      case RemoteStep():
        final code = step.tty
            ? await ssh.stream(step.host, step.script, tty: true)
            : await ssh.lines(step.host, step.script, _line);
        if (code != 0) throw StepError(step, 'exit code $code');
      case UploadStep():
        final code = await ssh.upload(
          step.host,
          step.localDir,
          step.remoteDir,
          delete: step.delete,
          onLine: _line,
        );
        if (code != 0) throw StepError(step, 'rsync exit code $code');
      case HealthStep():
        await _health(step);
      case PublicChecksStep():
        await _publicChecks(step);
      case ActionStep():
        await step.action();
      case ParallelStep():
        await _parallel(step);
    }
  }

  /// Runs the lanes of [step] at the same time. Each sub-step is reported
  /// as `lane: title` with its own time, so `history --verbose` shows the
  /// stages of every lane.
  Future<void> _parallel(ParallelStep step) async {
    final watch = Stopwatch()..start();
    final errors = <Object>[];
    var n = 0;
    Future<void> lane(Lane l) async {
      for (final s in l.steps) {
        final index = 1000 + n++;
        final title = '${l.name}: ${s.title}';
        final t0 = watch.elapsed;
        log.emit(StepStarted(index, 0, title));
        try {
          await runStep(s);
        } catch (e) {
          log.emit(StepFailed(index, title, '$e'));
          errors.add(
            e is StepError ? StepError(s, '${l.name}: ${e.message}') : e,
          );
          return;
        }
        log.emit(StepFinished(index, title, watch.elapsed - t0));
      }
    }

    await Future.wait(step.lanes.map(lane));
    if (errors.isNotEmpty) {
      throw StepError(step, errors.join('; '));
    }
  }

  Future<void> _publicChecks(PublicChecksStep step) async {
    var problems = <String>[];
    for (var i = 0; i < step.attempts; i++) {
      problems = [for (final c in step.checks) ?await publicCheckProblem(c)];
      if (problems.isEmpty) {
        log.info('public checks pass: ${step.checks.length}');
        return;
      }
      await Future<void>.delayed(Duration(seconds: step.intervalSeconds));
    }
    throw StepError(step, 'public checks failed: ${problems.join('; ')}');
  }

  Future<void> _health(HealthStep step) async {
    final script =
        '''
for i in \$(seq ${step.attempts}); do
  for u in ${step.remoteUrls.map(shq).join(' ')}; do
    if curl -fs -o /dev/null --max-time 5 "\$u"; then
      echo "healthy after \$i check(s): \$u"; exit 0
    fi
  done
  sleep ${step.intervalSeconds}
done
echo "no healthy answer from ${step.remoteUrls.join(' or ')}" >&2
exit 1
''';
    final code = await ssh.lines(step.host, script, _line);
    if (code != 0) {
      throw StepError(step, 'not healthy: ${step.remoteUrls.first}');
    }
    if (step.publicUrls.isEmpty) return;
    for (var i = 0; i < step.attempts; i++) {
      for (final pub in step.publicUrls) {
        if (await httpOk(pub)) {
          log.info('$pub answers');
          return;
        }
      }
      await Future<void>.delayed(Duration(seconds: step.intervalSeconds));
    }
    throw StepError(step, 'not healthy: ${step.publicUrls.first}');
  }
}

/// Why [check] fails now, or null when it passes.
Future<String?> publicCheckProblem(PublicCheck check) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.openUrl(check.method, Uri.parse(check.url));
    req.followRedirects = false;
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 15));
    final code = res.statusCode;
    final okStatus = check.status.isEmpty
        ? code >= 200 && code < 300
        : check.status.contains(code);
    if (!okStatus) return '${check.url}: status $code';
    final type = res.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    if (check.contentType != null &&
        !type.toLowerCase().contains(check.contentType!.toLowerCase())) {
      return '${check.url}: content type "$type", wanted "${check.contentType}"';
    }
    if (check.contains != null && !body.contains(check.contains!)) {
      return '${check.url}: the body lacks "${check.contains}"';
    }
    return null;
  } catch (e) {
    return '${check.url}: $e';
  } finally {
    client.close(force: true);
  }
}

/// Whether [url] answers with a 2xx status.
Future<bool> httpOk(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 15));
    await res.drain<void>();
    return res.statusCode >= 200 && res.statusCode < 300;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
