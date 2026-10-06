// Turns events into text for a terminal or a log file.

import 'events.dart';

/// One line of text for [e], or null when the event prints nothing.
/// [verbose] adds step timings; [color] adds ANSI colors.
String? renderEventText(
  PodshipEvent e, {
  bool verbose = false,
  bool color = false,
}) {
  String c(String code, String s) => color ? '\x1B[${code}m$s\x1B[0m' : s;
  String secs(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  return switch (e) {
    OperationStarted() =>
      verbose
          ? '${e.operation}${e.env == null ? '' : ' ${e.project}/${e.env} on ${e.host}'}${e.dryRun ? ' (dry run)' : ''}'
          : null,
    PlanReady() => null,
    StepStarted() => c(
      '1;36',
      '${e.recovery ? '↺' : '▶'} ${e.recovery ? '' : '${e.index}/${e.total} '}${e.title}',
    ),
    StepFinished() =>
      verbose ? c('2', '  ${e.title}: ${secs(e.duration)}') : null,
    StepFailed() => c('31', '✗ ${e.title} failed: ${e.error}'),
    LogLine() => switch (e.level) {
      LogLevel.detail => verbose ? c('2', '  ${e.text}') : null,
      LogLevel.ok => c('32', '✓ ${e.text}'),
      LogLevel.warn => c('33', '! ${e.text}'),
      LogLevel.error => c('31', '✗ ${e.text}'),
      LogLevel.info || LogLevel.output => e.text,
    },
    OperationFinished() =>
      e.result.ok
          ? c(
              '32',
              '✓ ${e.result.operation}${e.result.env == null ? '' : ' ${e.result.env}'}'
                  '${e.result.release == null ? '' : ' (${e.result.release})'}'
                  '${e.result.dryRun ? ': dry run, nothing was changed' : ': done in ${secs(e.result.duration)}'}',
            )
          : c('31', '✗ ${e.result.operation} failed: ${e.result.error}'),
  };
}
