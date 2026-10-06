// SSH and rsync, as subprocesses.
//
// podship never installs an agent on the server. Every remote action is a
// bash script passed to `ssh <host> bash -c '<script>'`. Data, secrets
// included, travels on stdin, never in arguments. Connections are shared
// with ControlMaster, so many small calls stay fast. `~/.ssh/config`
// aliases work, because podship calls the system `ssh`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A failed remote command.
class RemoteException implements Exception {
  RemoteException(this.host, this.exitCode, this.stderr);
  final String host;
  final int exitCode;
  final String stderr;
  @override
  String toString() {
    final e = stderr.trim();
    return 'ssh $host exited with $exitCode${e.isEmpty ? '' : ':\n$e'}';
  }
}

/// Quotes [s] for a POSIX shell.
String shq(String s) {
  if (s.isNotEmpty && RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(s)) {
    return s;
  }
  return "'${s.replaceAll("'", "'\\''")}'";
}

/// Runs commands on servers.
class Ssh {
  Ssh({this.extraOptions = const [], this.verbose = false});

  /// Extra options for every ssh call, like `-i key` in CI.
  final List<String> extraOptions;
  final bool verbose;

  // Unix socket paths are short (104 bytes on macOS), so not TMPDIR.
  static const _controlPath = '/tmp/podship-%C';

  List<String> options({bool tty = false}) => [
    '-o',
    'BatchMode=yes',
    '-o',
    'ConnectTimeout=20',
    '-o',
    'ServerAliveInterval=20',
    '-o',
    'ControlMaster=auto',
    '-o',
    'ControlPath=$_controlPath',
    '-o',
    'ControlPersist=120',
    if (tty) '-t',
    ...extraOptions,
  ];

  /// The `-e` argument for rsync, with the same options.
  String rsyncShell() => ['ssh', ...options()].map(shq).join(' ');

  List<String> _args(String host, String script, {bool tty = false}) => [
    ...options(tty: tty),
    host,
    'bash -c ${shq(script)}',
  ];

  /// Runs [script] and returns its stdout. Throws [RemoteException] on a
  /// non-zero exit. [stdin] is written to the script's standard input.
  Future<String> capture(String host, String script, {List<int>? stdin}) async {
    final r = await captureResult(host, script, stdin: stdin);
    if (r.exitCode != 0) throw RemoteException(host, r.exitCode, r.stderr);
    return r.stdout;
  }

  /// Like [capture], but returns the exit code instead of throwing.
  Future<({int exitCode, String stdout, String stderr})> captureResult(
    String host,
    String script, {
    List<int>? stdin,
  }) async {
    final proc = await Process.start('ssh', _args(host, script));
    final out = proc.stdout.transform(utf8.decoder).join();
    final err = proc.stderr.transform(utf8.decoder).join();
    if (stdin != null) proc.stdin.add(stdin);
    await proc.stdin.close();
    final code = await proc.exitCode;
    return (exitCode: code, stdout: await out, stderr: await err);
  }

  /// Runs [script] with its output shown live. Returns the exit code.
  Future<int> stream(String host, String script, {bool tty = false}) async {
    final proc = await Process.start(
      'ssh',
      _args(host, script, tty: tty),
      mode: tty ? ProcessStartMode.inheritStdio : ProcessStartMode.normal,
    );
    if (!tty) {
      await proc.stdin.close();
      await Future.wait([
        stdout.addStream(proc.stdout),
        stderr.addStream(proc.stderr),
      ]);
    }
    return proc.exitCode;
  }

  /// Runs [script] and passes each output line to [onLine]. Returns the
  /// exit code.
  Future<int> lines(
    String host,
    String script,
    void Function(String line, bool stderr) onLine,
  ) => runLines('ssh', _args(host, script), onLine);

  /// Copies [localDir] to [host]:[remoteDir] with rsync.
  Future<int> upload(
    String host,
    String localDir,
    String remoteDir, {
    bool delete = true,
    void Function(String line, bool stderr)? onLine,
  }) async {
    final args = [
      '-a',
      '--no-owner',
      '--no-group',
      if (delete) '--delete',
      '-e',
      rsyncShell(),
      '$localDir/',
      '$host:$remoteDir/',
    ];
    if (onLine != null) return runLines('rsync', args, onLine);
    final proc = await Process.start('rsync', args);
    await proc.stdin.close();
    await Future.wait([
      stdout.addStream(proc.stdout),
      stderr.addStream(proc.stderr),
    ]);
    return proc.exitCode;
  }
}

/// Runs [exe] with [args] and passes each output line to [onLine].
Future<int> runLines(
  String exe,
  List<String> args,
  void Function(String line, bool stderr) onLine, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final proc = await Process.start(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  await proc.stdin.close();
  Future<void> pump(Stream<List<int>> s, bool err) => s
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((l) => onLine(l, err));
  await Future.wait([pump(proc.stdout, false), pump(proc.stderr, true)]);
  return proc.exitCode;
}
