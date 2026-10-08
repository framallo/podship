// Plans: what a command will do, as data.
//
// Every mutating command first builds a [Plan]. `--dry-run` prints it and
// stops. Otherwise the [Executor] runs it step by step. Tests check plans
// without running them.

import '../config/config.dart';
import 'dart:async';

/// One thing a command does.
sealed class Step {
  const Step(this.title);
  final String title;

  /// A one-line description for `--dry-run`.
  String describe();
}

/// A local command (no shell unless the command is `bash -c`).
class LocalStep extends Step {
  const LocalStep(super.title, this.command, {this.cwd, this.env = const {}});
  final List<String> command;
  final String? cwd;
  final Map<String, String> env;
  @override
  String describe() =>
      '[local${cwd == null ? '' : ' in $cwd'}] ${command.join(' ')}';
}

/// A bash script that runs on the server through ssh.
class RemoteStep extends Step {
  const RemoteStep(super.title, this.host, this.script, {this.tty = false});
  final String host;
  final String script;

  /// Whether the step needs a terminal (`ssh -t`).
  final bool tty;
  @override
  String describe() {
    // Skip the shared header (set -e and helper functions), and show file
    // writes as one line instead of their content.
    final compact = script.replaceAllMapped(
      RegExp(
        r"cat > (\S+?)\.podship-tmp <<'(PODSHIP_EOF\w*)'\n[\s\S]*?\n\2\n(?:chmod \d+ \S+\n)?mv -f \S+ \S+\n",
      ),
      (m) => 'write ${m[1]}\n',
    );
    final lines = compact
        .trim()
        .split('\n')
        .where(
          (l) =>
              l != 'set -euo pipefail' &&
              !RegExp(r'^_[a-z0-9]+\(\)').hasMatch(l) &&
              !l.startsWith('export PATH='),
        )
        .toList();
    final shown = lines.length > 12
        ? [...lines.take(12), '  … ${lines.length - 12} more lines']
        : lines;
    return '[$host] ${shown.join('\n    ')}';
  }
}

/// Copies a local directory to the server with rsync.
class UploadStep extends Step {
  const UploadStep(
    super.title,
    this.host,
    this.localDir,
    this.remoteDir, {
    this.delete = true,
  });
  final String host;
  final String localDir;
  final String remoteDir;
  final bool delete;
  @override
  String describe() =>
      '[rsync] $localDir/ → $host:$remoteDir/${delete ? ' (--delete)' : ''}';
}

/// Waits until URLs answer with a 2xx status.
class HealthStep extends Step {
  const HealthStep(
    super.title,
    this.host,
    this.remoteUrls, {
    this.publicUrls = const [],
    this.attempts = 20,
    this.intervalSeconds = 6,
  });
  final String host;

  /// Fetched on the server.
  final List<String> remoteUrls;

  /// Fetched from this machine.
  final List<String> publicUrls;
  final int attempts;
  final int intervalSeconds;
  @override
  String describe() =>
      '[health] $host: ${remoteUrls.join(' or ')}${publicUrls.isEmpty ? '' : ', then ${publicUrls.join(' or ')}'}'
      ' ($attempts × ${intervalSeconds}s)';
}

/// Checks public URLs from this machine: status, content type and body
/// (`health.public_checks`). Retries until all pass or the attempts end.
class PublicChecksStep extends Step {
  const PublicChecksStep(
    super.title,
    this.checks, {
    this.attempts = 20,
    this.intervalSeconds = 6,
  });
  final List<PublicCheck> checks;
  final int attempts;
  final int intervalSeconds;
  @override
  String describe() =>
      '[public checks] ${checks.map((c) => c.describe()).join('; ')}'
      ' ($attempts × ${intervalSeconds}s)';
}

/// Work done in this process (for example, building the file list). The
/// description says what it does; the function does it.
class ActionStep extends Step {
  const ActionStep(super.title, this.what, this.action);
  final String what;
  final Future<void> Function() action;
  @override
  String describe() => '[local] $what';
}

/// One lane of a [ParallelStep]: steps that run in order.
class Lane {
  const Lane(this.name, this.steps);
  final String name;
  final List<Step> steps;
}

/// Lanes that run at the same time. The step fails when a lane fails,
/// after every lane has stopped.
class ParallelStep extends Step {
  const ParallelStep(super.title, this.lanes);
  final List<Lane> lanes;
  @override
  String describe() => [
    '[parallel] ${lanes.map((l) => l.name).join(' | ')}',
    for (final l in lanes)
      for (final s in l.steps)
        '  ${l.name}: ${s.title} — ${s.describe().split('\n').first}',
  ].join('\n    ');
}

/// A plan: steps, and the steps that undo a failure.
class Plan {
  Plan(
    this.title,
    this.steps, {
    this.recovery = const [],
    this.guardFrom,
    this.guardTo,
  });
  final String title;
  final List<Step> steps;

  /// Steps that run when a step at index [guardFrom] or later fails. A
  /// deploy uses them to switch back to the previous release.
  final List<Step> recovery;
  final int? guardFrom;

  /// The last guarded step (inclusive). Null means the last step.
  final int? guardTo;

  bool guards(int index) =>
      guardFrom != null &&
      index >= guardFrom! &&
      index <= (guardTo ?? steps.length - 1);

  String render() {
    final b = StringBuffer('Plan: $title\n');
    for (final (i, s) in steps.indexed) {
      b.writeln('${(i + 1).toString().padLeft(2)}. ${s.title}');
      b.writeln('    ${s.describe()}');
    }
    if (recovery.isNotEmpty) {
      b.writeln(
        'If a step from ${(guardFrom ?? 0) + 1} to '
        '${(guardTo ?? steps.length - 1) + 1} fails, podship runs:',
      );
      for (final s in recovery) {
        b.writeln('  - ${s.title}');
        b.writeln('    ${s.describe()}');
      }
    }
    return b.toString();
  }
}

/// A step failed.
class StepError implements Exception {
  StepError(this.step, this.message);
  final Step step;
  final String message;
  @override
  String toString() => '${step.title}: $message';
}
