// Runs plans and reports what happens as events.

import 'dart:io';

import '../api/events.dart';
import '../remote/ssh.dart';
import '../util/log.dart';
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
      case ActionStep():
        await step.action();
    }
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
