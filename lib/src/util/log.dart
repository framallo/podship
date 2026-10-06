// Console output.

import 'dart:io';

/// Writes progress to the terminal. Never pass secret values to it.
class Log {
  Log({this.verbose = false, this.quiet = false});
  final bool verbose;
  final bool quiet;

  bool get _color => stdout.hasTerminal && stdout.supportsAnsiEscapes;
  String _c(String code, String s) => _color ? '\x1B[${code}m$s\x1B[0m' : s;

  void step(String s) {
    if (!quiet) stdout.writeln(_c('1;36', '▶ $s'));
  }

  void info(String s) {
    if (!quiet) stdout.writeln(s);
  }

  void detail(String s) {
    if (verbose) stdout.writeln(_c('2', '  $s'));
  }

  void ok(String s) => stdout.writeln(_c('32', '✓ $s'));
  void warn(String s) => stderr.writeln(_c('33', '! $s'));
  void error(String s) => stderr.writeln(_c('31', '✗ $s'));
}
