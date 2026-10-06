// Personal access tokens for consoles, kept in the system's secret store:
// the macOS Keychain, the Linux Secret Service (`secret-tool`), or a 0600
// file as the last resort. `PODSHIP_TOKEN` overrides them (for CI).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class TokenStore {
  TokenStore({String? fileFallback})
    : _file =
          fileFallback ??
          p.join(
            Platform.environment['HOME'] ?? '.',
            '.config',
            'podship',
            'tokens.json',
          );

  final String _file;
  static const _service = 'podship';

  bool get _mac => Platform.isMacOS;
  bool get _secretTool =>
      Platform.isLinux &&
      Process.runSync('bash', ['-c', 'command -v secret-tool']).exitCode == 0;

  /// The token for [console], from `PODSHIP_TOKEN` or the store.
  String? read(String console) {
    final env = Platform.environment['PODSHIP_TOKEN'];
    if (env != null && env.isNotEmpty) return env;
    if (_mac) {
      final r = Process.runSync('security', [
        'find-generic-password',
        '-s',
        _service,
        '-a',
        console,
        '-w',
      ]);
      if (r.exitCode == 0) return (r.stdout as String).trim();
    } else if (_secretTool) {
      final r = Process.runSync('secret-tool', [
        'lookup',
        'service',
        _service,
        'url',
        console,
      ]);
      if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
        return (r.stdout as String).trim();
      }
    }
    return _readFile()[console];
  }

  /// Where [write] keeps tokens on this machine.
  String get where => _mac
      ? 'the macOS Keychain'
      : _secretTool
      ? 'the Secret Service'
      : _file;

  Future<void> write(String console, String token) async {
    if (_mac) {
      // -w reads the password from the argument; `security` has no stdin
      // mode for add-generic-password, so the token is visible to `ps` for
      // an instant. Use the file store if that matters on this machine.
      final r = await Process.run('security', [
        'add-generic-password',
        '-U',
        '-s',
        _service,
        '-a',
        console,
        '-w',
        token,
      ]);
      if (r.exitCode == 0) return;
    } else if (_secretTool) {
      final proc = await Process.start('secret-tool', [
        'store',
        '--label=podship $console',
        'service',
        _service,
        'url',
        console,
      ]);
      proc.stdin.write(token);
      await proc.stdin.close();
      if (await proc.exitCode == 0) return;
    }
    final m = _readFile()..[console] = token;
    _writeFile(m);
  }

  Future<void> delete(String console) async {
    if (_mac) {
      await Process.run('security', [
        'delete-generic-password',
        '-s',
        _service,
        '-a',
        console,
      ]);
    } else if (_secretTool) {
      await Process.run('secret-tool', [
        'clear',
        'service',
        _service,
        'url',
        console,
      ]);
    }
    final m = _readFile();
    if (m.remove(console) != null) _writeFile(m);
  }

  Map<String, String> _readFile() {
    final f = File(_file);
    if (!f.existsSync()) return {};
    try {
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  void _writeFile(Map<String, String> m) {
    final f = File(_file)..parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(m));
    Process.runSync('chmod', ['600', f.path]);
  }
}
