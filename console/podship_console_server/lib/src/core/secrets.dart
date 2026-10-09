import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Random tokens and their hashes. Tokens show once; only the SHA-256 is
/// stored.
class Secrets {
  static final _rng = Random.secure();
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// A random token of [length] base62 characters, with [prefix].
  static String token({String prefix = '', int length = 32}) {
    final b = StringBuffer(prefix);
    for (var i = 0; i < length; i++) {
      b.write(_alphabet[_rng.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  /// Hex SHA-256 of [token].
  static String hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  /// Compares two strings in constant time.
  static bool equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// The last 4 characters, for the UI (INT-5).
  static String hint(String value) =>
      value.length <= 4 ? '' : '…${value.substring(value.length - 4)}';
}
