// What every command needs: the config, ssh, the log and the global flags.

import 'dart:convert';
import 'dart:io';

import '../api/events.dart';
import '../config/config.dart';
import '../plan/executor.dart';
import '../plan/plan.dart';
import '../remote/ssh.dart';
import '../util/log.dart';
import 'scripts.dart';

/// The user cancelled, or a safety check stopped the command.
class Aborted implements Exception {
  Aborted(this.message);
  final String message;
  @override
  String toString() => message;
}

class Ctx {
  Ctx({
    required this.config,
    required this.ssh,
    required this.log,
    this.dryRun = false,
    this.yes = false,
  }) : executor = Executor(ssh, log);

  final PodshipConfig config;
  final Ssh ssh;
  final Log log;
  final bool dryRun;
  final bool yes;
  final Executor executor;

  /// Prints [plan] on `--dry-run`, else runs it.
  Future<void> run(Plan plan) async {
    log.emit(
      PlanReady(plan.title, [
        for (final s in plan.steps) s.title,
      ], plan.render()),
    );
    if (dryRun) {
      log.info('(dry run: nothing was changed)');
      return;
    }
    await executor.run(plan);
  }

  /// Asks a yes/no question. `--yes` answers yes. Without a terminal and
  /// without `--yes`, the answer is no.
  bool confirm(String question) {
    if (yes || dryRun) return true;
    if (!stdin.hasTerminal) {
      throw Aborted('$question Pass --yes to confirm without a terminal.');
    }
    stdout.write('$question [y/N] ');
    final a = stdin.readLineSync(encoding: utf8)?.trim().toLowerCase();
    return a == 'y' || a == 'yes';
  }

  /// Asks the user to type the project name. [typed] is the value of
  /// `--confirm <name>` for CI.
  void typeProjectName(String what, {String? typed}) {
    if (dryRun) return;
    final name = config.project;
    if (typed != null) {
      if (typed != name) throw Aborted('--confirm must be "$name"');
      return;
    }
    if (!stdin.hasTerminal) {
      throw Aborted(
        '$what needs you to type "$name". In CI pass --confirm $name.',
      );
    }
    stdout.write('$what\nType "$name" to continue: ');
    if (stdin.readLineSync(encoding: utf8)?.trim() != name) {
      throw Aborted('cancelled');
    }
  }

  /// The header of every remote script.
  String header(EnvConfig env) {
    final b = StringBuffer('set -euo pipefail\n$portableHelpers');
    if (env.remotePath != null) {
      b.writeln('export PATH=${shq(env.remotePath!)}:"\$PATH"');
    }
    return b.toString();
  }

  /// Runs [script] on [env]'s host and returns stdout.
  Future<String> query(EnvConfig env, String script, {List<int>? stdin}) =>
      ssh.capture(env.host, header(env) + script, stdin: stdin);
}
