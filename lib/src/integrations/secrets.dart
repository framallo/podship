// Credentials of the API integrations.
//
// The CLI keeps them in the system's secret store (macOS Keychain, Linux
// Secret Service, or a 0600 file), under `provider:cloudflare` and
// `provider:aws`. A console passes its own [SecretSource] (its encrypted
// store). The CLI also reads the podship console's workspace integrations
// (console_secrets.dart) before the Keychain. Environment variables come
// first, for CI:
// `CLOUDFLARE_API_TOKEN`, and `AWS_ACCESS_KEY_ID` with
// `AWS_SECRET_ACCESS_KEY` (and `AWS_SESSION_TOKEN`).
//
// No value read here is ever logged, printed or put in an event.

import 'dart:convert';
import 'dart:io';

import '../protocol/tokens.dart';
import 'console_secrets.dart';

/// Where credentials come from.
abstract class SecretSource {
  /// The value of [key], or null.
  String? read(String key);
}

/// The system's secret store, with environment overrides.
class SystemSecrets implements SecretSource {
  SystemSecrets({TokenStore? store, Map<String, String>? environment})
    : _store = store ?? TokenStore(),
      _env = environment ?? Platform.environment;
  final TokenStore _store;
  final Map<String, String> _env;

  @override
  String? read(String key) {
    switch (key) {
      case cloudflareTokenKey:
        final t = _env['CLOUDFLARE_API_TOKEN'];
        if (t != null && t.isNotEmpty) return t;
      case awsCredentialsKey:
        final id = _env['AWS_ACCESS_KEY_ID'];
        final secret = _env['AWS_SECRET_ACCESS_KEY'];
        if (id != null && id.isNotEmpty && secret != null) {
          return jsonEncode({
            'access_key_id': id,
            'secret_access_key': secret,
            'session_token': ?_env['AWS_SESSION_TOKEN'],
          });
        }
    }
    // The workspace's integration in the podship console, when the command
    // fetched it (ConsoleCredentials.prime); the Keychain is the fallback.
    final console = ConsoleCredentials.read(key);
    if (console != null) return console;
    // Not TokenStore.read: PODSHIP_TOKEN (a console token) must not stand
    // in for a provider credential.
    return _store.readStored(key);
  }
}

/// Fixed values (tests, or a console that already decrypted them).
class MapSecrets implements SecretSource {
  MapSecrets(this.values);
  final Map<String, String> values;
  @override
  String? read(String key) => values[key];
}

const cloudflareTokenKey = 'provider:cloudflare';
const awsCredentialsKey = 'provider:aws';

/// AWS credentials.
class AwsCredentials {
  AwsCredentials(this.accessKeyId, this.secretAccessKey, {this.sessionToken});

  /// From the JSON that `podship provider login aws` stores.
  factory AwsCredentials.fromJson(String text) {
    final j = jsonDecode(text) as Map;
    return AwsCredentials(
      '${j['access_key_id']}',
      '${j['secret_access_key']}',
      sessionToken: j['session_token'] as String?,
    );
  }

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;

  String toJson() => jsonEncode({
    'access_key_id': accessKeyId,
    'secret_access_key': secretAccessKey,
    'session_token': ?sessionToken,
  });

  /// The last 4 characters of the key id, to show which key is in use.
  String get hint =>
      '…${accessKeyId.length > 4 ? accessKeyId.substring(accessKeyId.length - 4) : ''}';
}
