// The log of an operation: it turns messages into events.

import '../api/events.dart';

/// Emits [LogLine] events. Never pass secret values to it.
class Log {
  Log(this.emit, {this.verbose = false, this.quiet = false});

  /// A log that drops everything (for tests).
  Log.silent() : emit = _drop, verbose = false, quiet = true;

  static void _drop(PodshipEvent _) {}

  final void Function(PodshipEvent event) emit;
  final bool verbose;
  final bool quiet;

  void info(String s) => emit(LogLine(s));
  void detail(String s) => emit(LogLine(s, level: LogLevel.detail));
  void ok(String s) => emit(LogLine(s, level: LogLevel.ok));
  void warn(String s) => emit(LogLine(s, level: LogLevel.warn));
  void error(String s) => emit(LogLine(s, level: LogLevel.error));
  void output(String s, {bool stderr = false}) =>
      emit(LogLine(s, level: LogLevel.output, stderr: stderr));
}
