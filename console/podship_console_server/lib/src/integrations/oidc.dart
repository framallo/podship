// The console as an OIDC issuer for AWS (decision: AWS through a role with
// web identity). AWS fetches the discovery document and the JWKS from the
// console's public URL and checks the RS256 signature of each token.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:serverpod/serverpod.dart';

import '../core/app_config.dart';
import '../core/secrets.dart';
import '../generated/protocol.dart';

class Oidc {
  /// The audience in every token and in the IAM provider's client id list.
  static const audience = 'sts.amazonaws.com';

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static Uint8List _bytes(BigInt n) {
    var hex = n.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static SecureRandom _random() {
    final r = Random.secure();
    return FortunaRandom()..seed(
      KeyParameter(
        Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
      ),
    );
  }

  static String _aad(String kid) => 'oidc:$kid';

  /// Makes a new RSA 2048 key and stores it encrypted.
  static Future<OidcKey> createKey(Session session) async {
    final gen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          _random(),
        ),
      );
    final pair = gen.generateKeyPair();
    final pub = pair.publicKey;
    final priv = pair.privateKey;
    final kid = Secrets.token(length: 16);
    final jwk = {
      'kty': 'RSA',
      'alg': 'RS256',
      'use': 'sig',
      'kid': kid,
      'n': _b64(_bytes(pub.modulus!)),
      'e': _b64(_bytes(pub.exponent!)),
    };
    final secret = jsonEncode({
      'n': priv.modulus!.toString(),
      'd': priv.privateExponent!.toString(),
      'p': priv.p!.toString(),
      'q': priv.q!.toString(),
    });
    return OidcKey.db.insertRow(
      session,
      OidcKey(
        kid: kid,
        privateKey: await AppConfig.instance.vault.encrypt(
          secret,
          aad: _aad(kid),
        ),
        publicJwk: jsonEncode(jwk),
      ),
    );
  }

  /// The active key, made on first use.
  static Future<OidcKey> activeKey(Session session) async {
    final k = await OidcKey.db.findFirstRow(
      session,
      where: (t) => t.retiredAt.equals(null),
      orderByList: (t) => [t.createdAt.desc()],
    );
    return k ?? await createKey(session);
  }

  /// Retires every key and makes a new one: tokens signed before no longer
  /// verify, so no new AWS session can start with them (INT-16).
  static Future<void> rotate(Session session) async {
    final now = DateTime.now().toUtc();
    for (final k in await OidcKey.db.find(
      session,
      where: (t) => t.retiredAt.equals(null),
    )) {
      await OidcKey.db.updateRow(session, k.copyWith(retiredAt: now));
    }
    await createKey(session);
  }

  /// A signed token for [subject], valid for 5 minutes.
  static Future<String> sign(Session session, String subject) async {
    final key = await activeKey(session);
    final raw =
        jsonDecode(
              await AppConfig.instance.vault.decrypt(
                key.privateKey,
                aad: _aad(key.kid),
              ),
            )
            as Map<String, Object?>;
    final priv = RSAPrivateKey(
      BigInt.parse(raw['n'] as String),
      BigInt.parse(raw['d'] as String),
      BigInt.parse(raw['p'] as String),
      BigInt.parse(raw['q'] as String),
    );
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final header = {'alg': 'RS256', 'typ': 'JWT', 'kid': key.kid};
    final claims = {
      'iss': AppConfig.instance.publicUrl,
      'sub': subject,
      'aud': audience,
      'iat': now,
      'nbf': now - 30,
      'exp': now + 300,
      'jti': Secrets.token(length: 16),
    };
    final input =
        '${_b64(utf8.encode(jsonEncode(header)))}.'
        '${_b64(utf8.encode(jsonEncode(claims)))}';
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
    final sig = signer.generateSignature(
      Uint8List.fromList(utf8.encode(input)),
    );
    return '$input.${_b64(sig.bytes)}';
  }

  /// `/.well-known/openid-configuration`.
  static Map<String, Object?> discovery() {
    final iss = AppConfig.instance.publicUrl;
    return {
      'issuer': iss,
      'jwks_uri': '$iss/.well-known/jwks.json',
      'response_types_supported': ['id_token'],
      'subject_types_supported': ['public'],
      'id_token_signing_alg_values_supported': ['RS256'],
      'claims_supported': ['sub', 'aud', 'iss', 'iat', 'exp'],
    };
  }

  /// `/.well-known/jwks.json`: the active key only.
  static Future<Map<String, Object?>> jwks(Session session) async {
    final k = await activeKey(session);
    return {
      'keys': [jsonDecode(k.publicJwk)],
    };
  }

  /// The subject of a workspace's tokens; the role's trust policy names it.
  static String subjectOf(Workspace ws) => 'workspace:${ws.slug}';
}
