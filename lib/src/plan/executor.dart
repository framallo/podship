// Runs plans.

import 'dart:io';

import '../remote/ssh.dart';
import '../util/log.dart';
import 'plan.dart';

/// Runs the steps of a [Plan] in order.
class Executor {
  Executor(this.ssh, this.log);
  final Ssh ssh;
  final Log log;

  /// Runs [plan]. On a failure at or after `guardFrom`, runs the recovery
  /// steps, then throws the first failure.
  Future<void> run(Plan plan) async {
    final watch = Stopwatch()..start();
    for (final (i, step) in plan.steps.indexed) {
      final t0 = watch.elapsed;
      log.step('${i + 1}/${plan.steps.length} ${step.title}');
      try {
        await runStep(step);
      } catch (e) {
        log.error('${step.title} failed: $e');
        if (plan.guards(i) && plan.recovery.isNotEmpty) {
          log.warn('Recovering');
          for (final r in plan.recovery) {
            log.step(r.title);
            try {
              await runStep(r);
            } catch (e2) {
              log.error('${r.title} failed too: $e2');
            }
          }
        }
        rethrow;
      }
      log.detail('done in ${_secs(watch.elapsed - t0)}');
    }
    log.ok('${plan.title}: done in ${_secs(watch.elapsed)}');
  }

  static String _secs(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

  Future<void> runStep(Step step) async {
    switch (step) {
      case LocalStep():
        final proc = await Process.start(
          step.command.first,
          step.command.sublist(1),
          workingDirectory: step.cwd,
          environment: step.env.isEmpty ? null : step.env,
          mode: ProcessStartMode.inheritStdio,
        );
        final code = await proc.exitCode;
        if (code != 0) throw StepFailed(step, 'exit code $code');
      case RemoteStep():
        final code = await ssh.stream(step.host, step.script, tty: step.tty);
        if (code != 0) throw StepFailed(step, 'exit code $code');
      case UploadStep():
        final code = await ssh.upload(
          step.host,
          step.localDir,
          step.remoteDir,
          delete: step.delete,
        );
        if (code != 0) throw StepFailed(step, 'rsync exit code $code');
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
  if curl -fsS -o /dev/null --max-time 5 ${shq(step.remoteUrl)}; then
    echo "healthy after \$i check(s)"; exit 0
  fi
  sleep ${step.intervalSeconds}
done
echo "no healthy answer from ${step.remoteUrl}" >&2
exit 1
''';
    final code = await ssh.stream(step.host, script);
    if (code != 0) throw StepFailed(step, 'not healthy: ${step.remoteUrl}');
    final pub = step.publicUrl;
    if (pub == null) return;
    for (var i = 0; i < step.attempts; i++) {
      if (await httpOk(pub)) {
        log.detail('$pub answers');
        return;
      }
      await Future<void>.delayed(Duration(seconds: step.intervalSeconds));
    }
    throw StepFailed(step, 'not healthy: $pub');
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
