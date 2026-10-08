// self update, self path: the compiled podship executable.
//
// `dart pub global activate` runs podship from source: every start resolves
// dependencies and compiles. `podship self update` builds a native
// executable with `dart compile exe` into `~/.podship/bin/podship`, and
// when the `podship` on PATH is the script pub wrote, replaces that script
// with a two-line shim that runs the executable. Startup becomes instant.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/podship.dart' show podshipVersion;
import '../ops/context.dart';
import 'base.dart';

/// `~/.podship` (or `$PODSHIP_HOME`).
String podshipHomeDir([Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  return e['PODSHIP_HOME'] ?? p.join(e['HOME'] ?? '.', '.podship');
}

/// Where the compiled executable goes.
String compiledPath([Map<String, String>? env]) =>
    p.join(podshipHomeDir(env), 'bin', 'podship');

/// The podship source checkout this process runs from, or null when it is
/// a compiled executable or the location is unknown.
String? sourceDirOfThisProcess() {
  // `dart run` / `pub global run`: the script is bin/podship.dart (or a
  // snapshot next to it); a compiled exe has no .dart script.
  final script = Platform.script.toFilePath();
  if (script.endsWith('.dart')) {
    final dir = p.dirname(p.dirname(script));
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
  }
  // The path pub recorded when the package was activated from a folder.
  final lock = File(
    p.join(
      Platform.environment['PUB_CACHE'] ??
          p.join(Platform.environment['HOME'] ?? '.', '.pub-cache'),
      'global_packages',
      'podship',
      'pubspec.lock',
    ),
  );
  if (lock.existsSync()) {
    final m = RegExp(
      r'^\s+path: "?([^"\n]+)"?\s*$',
      multiLine: true,
    ).firstMatch(lock.readAsStringSync());
    if (m != null && File(p.join(m[1]!, 'pubspec.yaml')).existsSync()) {
      return m[1];
    }
  }
  return null;
}

/// Whether [file] is the launcher script that `pub global activate` wrote.
bool isPubScript(File file) {
  if (!file.existsSync()) return false;
  try {
    final head = file.readAsStringSync();
    return head.length < 2000 &&
        head.startsWith('#!') &&
        (head.contains('created by pub') ||
            head.contains('dart pub global run podship'));
  } catch (_) {
    return false;
  }
}

/// Whether [file] is the shim that [shimScript] writes.
bool isShim(File file) {
  try {
    return file.existsSync() &&
        file.readAsStringSync().contains('podship self update');
  } catch (_) {
    return false;
  }
}

/// The shim that replaces pub's script: it runs the compiled executable.
String shimScript(String exe) =>
    '#!/bin/sh\n# podship: runs the compiled executable (podship self update).\nexec "$exe" "\$@"\n';

class SelfUpdateCommand extends PodshipCommand {
  SelfUpdateCommand() {
    argParser
      ..addOption(
        'from',
        help:
            'The podship source folder to build (default: the checkout this podship runs from, or ~/.podship/src/podship).',
      )
      ..addOption(
        'repo',
        defaultsTo: 'https://github.com/framallo/podship',
        help: 'The git repository to clone when there is no source folder.',
      )
      ..addFlag(
        'pull',
        defaultsTo: true,
        help: 'git pull --ff-only in the source folder before building.',
      )
      ..addFlag(
        'shim',
        defaultsTo: true,
        help:
            'Replace the `podship` script that pub wrote on PATH with a shim that runs the executable.',
      );
  }
  @override
  String get name => 'update';
  @override
  String get description =>
      'Build the compiled podship executable (instant startup) into ~/.podship/bin and point the `podship` on PATH at it.';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;

  @override
  Future<int> execute() async {
    final a = argResults!;
    var src = a['from'] as String? ?? sourceDirOfThisProcess();
    final home = podshipHomeDir();
    if (src == null) {
      src = p.join(home, 'src', 'podship');
      if (!Directory(src).existsSync()) {
        log.info('cloning ${a['repo']} into $src');
        if (!dryRun) {
          final r = await Process.run('git', [
            'clone',
            '-q',
            a['repo'] as String,
            src,
          ]);
          if (r.exitCode != 0) throw Aborted('git clone failed: ${r.stderr}');
        }
      }
    }
    if (!File(p.join(src, 'pubspec.yaml')).existsSync()) {
      throw Aborted('$src is not a podship checkout');
    }
    final exe = compiledPath();
    log.info('source: $src');
    log.info('executable: $exe');
    if (dryRun) {
      log.info('(dry run: nothing was built)');
      return 0;
    }
    if (a['pull'] == true && Directory(p.join(src, '.git')).existsSync()) {
      final dirty = await Process.run('git', [
        'status',
        '--porcelain',
        '--untracked-files=no',
      ], workingDirectory: src);
      if ((dirty.stdout as String).trim().isEmpty) {
        final r = await Process.run('git', [
          'pull',
          '-q',
          '--ff-only',
        ], workingDirectory: src);
        if (r.exitCode != 0) {
          log.warn(
            'git pull failed (${(r.stderr as String).trim()}); building what is there',
          );
        }
      } else {
        log.warn('$src has uncommitted changes: not pulling, building them');
      }
    }
    var r = await Process.run('dart', ['pub', 'get'], workingDirectory: src);
    if (r.exitCode != 0) throw Aborted('dart pub get failed: ${r.stderr}');
    Directory(p.dirname(exe)).createSync(recursive: true);
    final tmp = '$exe.new';
    log.info('dart compile exe bin/podship.dart');
    r = await Process.run('dart', [
      'compile',
      'exe',
      'bin/podship.dart',
      '-o',
      tmp,
    ], workingDirectory: src);
    if (r.exitCode != 0) throw Aborted('dart compile exe failed: ${r.stderr}');
    File(tmp).renameSync(exe);
    await Process.run('chmod', ['755', exe]);
    final v = await Process.run(exe, ['--version']);
    log.ok('built ${(v.stdout as String).trim()} at $exe');

    if (a['shim'] == true) {
      final which = await Process.run('which', ['-a', 'podship']);
      final onPath = (which.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      var shimmed = false;
      for (final path in onPath) {
        final f = File(path);
        if (p.canonicalize(path) == p.canonicalize(exe)) {
          shimmed = true;
          continue;
        }
        if (isPubScript(f) || isShim(f)) {
          f.writeAsStringSync(shimScript(exe));
          await Process.run('chmod', ['755', path]);
          log.ok('$path runs the executable');
          shimmed = true;
        }
      }
      if (!shimmed) {
        log.warn(
          'no `podship` on PATH points at the executable; add ${p.dirname(exe)} to PATH '
          '(or run `dart pub global activate --source path $src` first, then `podship self update`)',
        );
      }
    }
    return 0;
  }
}

class SelfPathCommand extends PodshipCommand {
  @override
  String get name => 'path';
  @override
  String get description =>
      'Where this podship runs from: a compiled executable or a source checkout.';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    final src = sourceDirOfThisProcess();
    final exe = Platform.resolvedExecutable;
    final compiled = !Platform.script.toFilePath().endsWith('.dart');
    if (json) {
      printJson({
        'version': podshipVersion,
        'compiled': compiled,
        'executable': exe,
        'source': ?src,
        'compiled_path': compiledPath(),
      });
      return 0;
    }
    stdout.writeln('podship $podshipVersion');
    stdout.writeln(
      compiled
          ? 'compiled executable: $exe'
          : 'running from source with ${p.basename(exe)}: ${Platform.script.toFilePath()}',
    );
    if (src != null) stdout.writeln('source: $src');
    if (!compiled) {
      stdout.writeln('run `podship self update` for instant startup');
    }
    return 0;
  }
}
