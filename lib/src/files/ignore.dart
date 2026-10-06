// File selection in gitignore syntax.
//
// A release ships the files of the project, minus what `.gitignore` and
// `.podshipignore` exclude, with the `files:` rules of `podship.yaml` applied
// last. `!pattern` includes files again. Unlike git, a file under an excluded
// directory can be included again by a later rule that names the file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// One rule from an ignore file.
class IgnoreRule {
  IgnoreRule._(this.source, this.base, this.negate, this.dirOnly, this._re);

  /// Parses [line] of an ignore file located in [base] (a relative
  /// directory, '' for the root). Returns null for blank lines and comments.
  static IgnoreRule? parse(String line, {String base = ''}) {
    var s = line;
    if (s.endsWith('\r')) s = s.substring(0, s.length - 1);
    // Trailing spaces are ignored unless escaped.
    while (s.endsWith(' ') && !s.endsWith(r'\ ')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty || s.startsWith('#')) return null;
    var negate = false;
    if (s.startsWith('!')) {
      negate = true;
      s = s.substring(1);
    } else if (s.startsWith(r'\!') || s.startsWith(r'\#')) {
      s = s.substring(1);
    }
    var dirOnly = false;
    if (s.endsWith('/')) {
      dirOnly = true;
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;
    final anchored = s.contains('/');
    if (s.startsWith('/')) s = s.substring(1);
    final body = globToRegex(s);
    final re = RegExp(anchored ? '^$body\$' : '^(?:.*/)?$body\$');
    return IgnoreRule._(line, base, negate, dirOnly, re);
  }

  final String source;

  /// The directory of the ignore file, relative to the root.
  final String base;
  final bool negate;
  final bool dirOnly;
  final RegExp _re;

  /// Whether this rule matches [path] (relative to the root).
  bool matches(String path, {required bool isDir}) {
    if (dirOnly && !isDir) return false;
    String rel;
    if (base.isEmpty) {
      rel = path;
    } else if (path.startsWith('$base/')) {
      rel = path.substring(base.length + 1);
    } else {
      return false;
    }
    return _re.hasMatch(rel);
  }
}

/// Converts a gitignore glob to a regular expression body.
String globToRegex(String glob) {
  final b = StringBuffer();
  var i = 0;
  while (i < glob.length) {
    final c = glob[i];
    if (c == '*') {
      final double = i + 1 < glob.length && glob[i + 1] == '*';
      if (double) {
        final atStart = i == 0 || glob[i - 1] == '/';
        final slashAfter = i + 2 < glob.length && glob[i + 2] == '/';
        final atEnd = i + 2 == glob.length;
        if (atStart && slashAfter) {
          b.write('(?:.*/)?');
          i += 3;
          continue;
        }
        if (atStart && atEnd) {
          b.write('.*');
          i += 2;
          continue;
        }
        b.write('.*');
        i += 2;
        continue;
      }
      b.write('[^/]*');
    } else if (c == '?') {
      b.write('[^/]');
    } else if (c == '[') {
      final end = glob.indexOf(']', i + 1);
      if (end < 0) {
        b.write(r'\[');
      } else {
        var cls = glob.substring(i + 1, end);
        if (cls.startsWith('!')) cls = '^${cls.substring(1)}';
        b.write('[${cls.replaceAll(r'\', r'\\')}]');
        i = end;
      }
    } else if (c == r'\' && i + 1 < glob.length) {
      b.write(RegExp.escape(glob[i + 1]));
      i++;
    } else {
      b.write(RegExp.escape(c));
    }
    i++;
  }
  return b.toString();
}

/// Paths that never ship, whatever the rules say: they hold secrets or
/// local state.
final _neverShip = [
  for (final r in [
    '.git/',
    '.dart_tool/',
    '.podship/',
    '.env',
    '.env.*',
    'passwords.yaml',
    '*.pem',
    '*.p8',
    'id_rsa*',
    'id_ed25519*',
  ])
    IgnoreRule.parse(r)!,
];

/// Whether [path] is one of the paths that never ship.
bool neverShips(String path) {
  final parts = p.posix.split(path);
  for (var i = 1; i <= parts.length; i++) {
    final sub = p.posix.joinAll(parts.take(i));
    final isDir = i < parts.length;
    for (final r in _neverShip) {
      // `.env.ejemplo`-style templates are fine; only exact secret names.
      if (r.source == '.env.*' && !isDir) {
        final name = parts.last;
        if (name.endsWith('.example') ||
            name.endsWith('.ejemplo') ||
            name.endsWith('.sample') ||
            name.endsWith('.template')) {
          continue;
        }
      }
      if (r.matches(sub, isDir: isDir)) return true;
    }
  }
  return false;
}

/// An ordered set of rules. The last rule that matches decides.
class FileRules {
  FileRules(this.rules);
  final List<IgnoreRule> rules;

  /// Whether [path] is selected (shipped).
  bool includes(String path) {
    if (neverShips(path)) return false;
    final parts = p.posix.split(path);
    bool? excluded;
    for (final r in rules) {
      // A rule matches the file, or any directory above it.
      var hit = r.matches(path, isDir: false);
      for (var i = 1; !hit && i < parts.length; i++) {
        hit = r.matches(p.posix.joinAll(parts.take(i)), isDir: true);
        // A negated rule only re-includes when it names the file or uses a
        // glob that covers it; a directory match is enough for both.
      }
      if (hit) excluded = !r.negate;
    }
    return !(excluded ?? false);
  }
}

/// The names of the per-directory ignore files, in the order they apply.
const ignoreFileNames = ['.gitignore', '.podshipignore'];

/// Lists the files under [root] that a release ships.
///
/// Rules come from every `.gitignore` and `.podshipignore` (parents before
/// children), then from [extraRules] (anchored at the root).
List<String> selectFiles(String root, {List<String> extraRules = const []}) {
  final files = <String>[];
  final ruleFiles = <String, List<IgnoreRule>>{};

  void walk(Directory dir, String rel) {
    final entries = dir.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final e in entries) {
      final name = p.basename(e.path);
      final r = rel.isEmpty ? name : '$rel/$name';
      if (e is Directory) {
        if (name == '.git' || name == '.dart_tool') continue;
        walk(e, r);
      } else if (e is File || e is Link) {
        if (ignoreFileNames.contains(name)) {
          ruleFiles['$rel\u0000$name'] = [
            for (final line in File(e.path).readAsLinesSync())
              ?IgnoreRule.parse(line, base: rel),
          ];
        }
        files.add(r);
      }
    }
  }

  walk(Directory(root), '');
  // Parents before children; .gitignore before .podshipignore.
  final keys = ruleFiles.keys.toList()
    ..sort((a, b) {
      final da = a.split('\u0000').first, db = b.split('\u0000').first;
      final depth =
          (da.isEmpty ? 0 : '/'.allMatches(da).length + 1) -
          (db.isEmpty ? 0 : '/'.allMatches(db).length + 1);
      if (depth != 0) return depth;
      final c = da.compareTo(db);
      if (c != 0) return c;
      return ignoreFileNames
          .indexOf(a.split('\u0000').last)
          .compareTo(ignoreFileNames.indexOf(b.split('\u0000').last));
    });
  final rules = FileRules([
    for (final k in keys) ...ruleFiles[k]!,
    for (final line in extraRules) ?IgnoreRule.parse(line),
  ]);
  return [
    for (final f in files)
      if (rules.includes(f)) f,
  ];
}
