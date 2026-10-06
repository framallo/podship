// Edits Serverpod `passwords.yaml` files, keeping comments.

import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

class PasswordsFile {
  PasswordsFile(String text) : _editor = YamlEditor(text);
  YamlEditor _editor;

  YamlMap get _root {
    final v = _editor.parseAt([]);
    return v is YamlMap ? v : YamlMap();
  }

  /// Section names, like `shared` and `production`.
  List<String> get sections => [for (final k in _root.keys) '$k'];

  /// Key names in [section].
  List<String> keys(String section) {
    final s = _root[section];
    return s is YamlMap ? [for (final k in s.keys) '$k'] : const [];
  }

  String? get(String section, String key) {
    final s = _root[section];
    if (s is! YamlMap || s[key] == null) return null;
    return '${s[key]}';
  }

  void set(String section, String key, String value) {
    final root = _editor.parseAt([]);
    if (root is! YamlMap || root[section] is! YamlMap) {
      // Append a block-style section; yaml_edit cannot add to an empty
      // document and would write flow style.
      if (root is YamlMap && root.containsKey(section))
        _editor.remove([section]);
      final text = _editor.toString().trimRight();
      _editor = YamlEditor(
        '${text.isEmpty ? '' : '$text\n'}$section:\n  $key: ${jsonEncode(value)}\n',
      );
    } else {
      _editor.update([section, key], value);
    }
  }

  bool unset(String section, String key) {
    final s = _root[section];
    if (s is! YamlMap || !s.containsKey(key)) return false;
    _editor.remove([section, key]);
    return true;
  }

  @override
  String toString() {
    final t = _editor.toString();
    return t.endsWith('\n') ? t : '$t\n';
  }
}
