// Processes for the server-side agent: one command, or a pipeline of
// commands, with stdin and stdout from or to files. Tests replace [Proc]
// with a fake that records the commands.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The result of a command or a pipeline. With a stdout file, [stdout] is
/// empty.
class ProcResult {
  ProcResult(this.code, {this.stdout = '', this.stderr = ''});
  final int code;
  final String stdout;
  final String stderr;
  bool get ok => code == 0;
}

/// Runs processes for the agent.
abstract class Proc {
  /// Runs [cmd]. stdin comes from [stdinText] or [stdinFile]; stdout goes
  /// to [stdoutFile] or into the result. stderr is shown and kept.
  Future<ProcResult> run(
    List<String> cmd, {
    String? stdinText,
    String? stdinFile,
    String? stdoutFile,
    Map<String, String>? env,
  });

  /// Runs [cmds] with the stdout of each one as the stdin of the next.
  /// The code is the first nonzero code (like `set -o pipefail`).
  Future<ProcResult> pipe(
    List<List<String>> cmds, {
    String? stdinFile,
    String? stdoutFile,
  });

  /// Waits [d]. Tests do not wait.
  Future<void> sleep(Duration d);
}

/// The real processes.
class SystemProc implements Proc {
  SystemProc({IOSink? errors}) : errors = errors ?? stderr;

  /// Where the stderr of the commands goes.
  final IOSink errors;

  Future<String> _err(Stream<List<int>> s, StringBuffer keep) => s
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((l) {
        keep.writeln(l);
        errors.writeln(l);
      })
      .then((_) => keep.toString());

  @override
  Future<ProcResult> run(
    List<String> cmd, {
    String? stdinText,
    String? stdinFile,
    String? stdoutFile,
    Map<String, String>? env,
  }) async {
    final proc = await Process.start(
      cmd.first,
      cmd.sublist(1),
      environment: env,
    );
    final err = StringBuffer();
    final errDone = _err(proc.stderr, err);
    final outDone = stdoutFile != null
        ? proc.stdout.pipe(File(stdoutFile).openWrite()).then((_) => '')
        : proc.stdout.transform(utf8.decoder).join();
    if (stdinFile != null) {
      await File(stdinFile).openRead().pipe(proc.stdin);
    } else {
      if (stdinText != null) proc.stdin.write(stdinText);
      await proc.stdin.close();
    }
    final out = await outDone;
    await errDone;
    return ProcResult(await proc.exitCode, stdout: out, stderr: err.toString());
  }

  @override
  Future<ProcResult> pipe(
    List<List<String>> cmds, {
    String? stdinFile,
    String? stdoutFile,
  }) async {
    final procs = <Process>[];
    for (final c in cmds) {
      procs.add(await Process.start(c.first, c.sublist(1)));
    }
    final err = StringBuffer();
    final errs = [for (final p in procs) _err(p.stderr, err)];
    final links = <Future<void>>[];
    if (stdinFile != null) {
      links.add(File(stdinFile).openRead().pipe(procs.first.stdin));
    } else {
      links.add(procs.first.stdin.close());
    }
    for (var i = 0; i + 1 < procs.length; i++) {
      links.add(procs[i].stdout.pipe(procs[i + 1].stdin));
    }
    final last = procs.last.stdout;
    final outDone = stdoutFile != null
        ? last.pipe(File(stdoutFile).openWrite()).then((_) => '')
        : last.transform(utf8.decoder).join();
    final out = await outDone;
    // A reader that exits early breaks the pipe of the writer: ignore it,
    // the exit codes tell what happened.
    for (final l in links) {
      try {
        await l;
      } catch (_) {}
    }
    await Future.wait(errs);
    var code = 0;
    for (final p in procs) {
      final c = await p.exitCode;
      if (code == 0 && c != 0) code = c;
    }
    return ProcResult(code, stdout: out, stderr: err.toString());
  }

  @override
  Future<void> sleep(Duration d) => Future.delayed(d);
}
