import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encryption at rest of provider credentials with AES-256-GCM (INT-4).
///
/// Format: base64( nonce(12) || ciphertext || tag(16) ). The `aad` binds a
/// value to its row (`integration:<workspace>:<provider>`): a value copied to
/// another row does not decrypt.
class Vault {
  Vault(List<int> key)
    : _key = SecretKeyData(key),
      assert(key.length == 32, 'the key must have 32 bytes');

  /// From the base64 key in passwords.yaml (`integrationKey`).
  factory Vault.fromBase64(String key) {
    final bytes = base64Decode(base64.normalize(key.trim()));
    if (bytes.length != 32) {
      throw ArgumentError('integrationKey must be 32 bytes in base64');
    }
    return Vault(bytes);
  }

  final SecretKeyData _key;
  static final _algo = AesGcm.with256bits();

  Future<String> encrypt(String plaintext, {required String aad}) async {
    final box = await _algo.encrypt(
      utf8.encode(plaintext),
      secretKey: _key,
      aad: utf8.encode(aad),
    );
    return base64Encode(
      Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]),
    );
  }

  Future<String> decrypt(String ciphertext, {required String aad}) async {
    final bytes = base64Decode(ciphertext);
    if (bytes.length < 12 + 16) {
      throw const FormatException('ciphertext too short');
    }
    final clear = await _algo.decrypt(
      SecretBox(
        bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: _key,
      aad: utf8.encode(aad),
    );
    return utf8.decode(clear);
  }
}
