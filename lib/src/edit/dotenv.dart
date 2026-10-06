// Edits `.env` files without losing comments or order.
//
// A variable is "plain" (not secret) when the line above it is the comment
// `# podship: plain`, or when podship.yaml lists it in `plain_env`. Plain
// values may be printed; secret values never are.

/// The marker comment for plain variables.
const plainMarker = '# podship: plain';

final _line = RegExp(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$');

/// A valid variable name.
bool validEnvName(String name) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name);

class DotEnv {
  DotEnv(String text)
    : lines = text.isEmpty
          ? []
          : (text.endsWith('\n') ? text.substring(0, text.length - 1) : text)
                .split('\n');

  final List<String> lines;

  int _index(String key) {
    for (var i = 0; i < lines.length; i++) {
      final m = _line.firstMatch(lines[i]);
      if (m != null && m[1] == key) return i;
    }
    return -1;
  }

  /// Variable names, in file order.
  List<String> get names => [
    for (final l in lines)
      if (_line.firstMatch(l) case final m?) m[1]!,
  ];

  bool has(String key) => _index(key) >= 0;

  /// Whether the line above [key] is the plain marker.
  bool markedPlain(String key) {
    final i = _index(key);
    return i > 0 && lines[i - 1].trim() == plainMarker;
  }

  /// The unquoted value of [key], or null.
  String? get(String key) {
    final i = _index(key);
    if (i < 0) return null;
    return unquote(_line.firstMatch(lines[i])![2]!.trim());
  }

  /// Sets [key] to [value]. Marks it plain when [plain] is true.
  void set(String key, String value, {bool plain = false}) {
    if (!validEnvName(key)) throw ArgumentError('invalid name: $key');
    final line = '$key=${quote(value)}';
    final i = _index(key);
    if (i >= 0) {
      lines[i] = line;
      final marked = i > 0 && lines[i - 1].trim() == plainMarker;
      if (plain && !marked) {
        lines.insert(i, plainMarker);
      } else if (!plain && marked) {
        lines.removeAt(i - 1);
      }
    } else {
      if (plain) lines.add(plainMarker);
      lines.add(line);
    }
  }

  /// Removes [key]. Returns false when it was not there.
  bool unset(String key) {
    final i = _index(key);
    if (i < 0) return false;
    lines.removeAt(i);
    if (i > 0 && lines[i - 1].trim() == plainMarker) lines.removeAt(i - 1);
    return true;
  }

  @override
  String toString() => lines.isEmpty ? '' : '${lines.join('\n')}\n';

  /// Quotes [v] for a compose `.env` file.
  static String quote(String v) {
    if (RegExp(r'^[A-Za-z0-9_./:@+=,%-]*$').hasMatch(v)) return v;
    if (!v.contains("'") && !v.contains('\n')) return "'$v'";
    final e = v
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll(r'$', r'$$');
    return '"$e"';
  }

  /// Reads a value written by [quote] or by hand.
  static String unquote(String v) {
    if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
      return v.substring(1, v.length - 1);
    }
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      final s = v.substring(1, v.length - 1);
      final b = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (s[i] == r'\' && i + 1 < s.length) {
          final n = s[++i];
          b.write(n == 'n' ? '\n' : n);
        } else if (s[i] == r'$' && i + 1 < s.length && s[i + 1] == r'$') {
          b.write(r'$');
          i++;
        } else {
          b.write(s[i]);
        }
      }
      return b.toString();
    }
    // Unquoted: a trailing ` # comment` is not part of the value.
    final hash = v.indexOf(' #');
    return (hash >= 0 ? v.substring(0, hash) : v).trim();
  }
}
