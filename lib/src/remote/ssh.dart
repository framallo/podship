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

  static String get _controlPath {
    final dir = Platform.environment['TMPDIR'] ?? '/tmp';
    return '$dir/podship-ssh-%C';
  }

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

  /// Copies [localDir] to [host]:[remoteDir] with rsync.
  Future<int> upload(
    String host,
    String localDir,
    String remoteDir, {
    bool delete = true,
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
    final proc = await Process.start('rsync', args);
    await proc.stdin.close();
    await Future.wait([
      stdout.addStream(proc.stdout),
      stderr.addStream(proc.stderr),
    ]);
    return proc.exitCode;
  }
}
