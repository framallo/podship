// Provider credentials from the podship console (the workspace's
// integrations), so `podship email setup`, `dns`, `tunnel` and the watch work
// with no Keychain login. podship-design: decisions/2026-10-09-integrations-phase-1.
//
// The console URL: `PODSHIP_CONSOLE_URL`, else `console.url` in
// `~/.podship/config.yaml`, else `console.url` in the podship.yaml of the
// current folder. The token: the one `podship login <url>` stored.
//
// [SystemSecrets] reads in this order: environment variables, the console
// (when [ConsoleCredentials.prime] fetched it), the Keychain. Values stay in
// memory; nothing here prints, logs or writes a value.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../protocol/tokens.dart';
import 'secrets.dart';

class ConsoleCredentials {
  ConsoleCredentials._();

  static final Map<String, String> _cache = {};
  static DateTime? _awsExpires;
  static Timer? _refresh;

  /// The value fetched for [key] (`provider:cloudflare`, `provider:aws`).
  static String? read(String key) {
    if (key == awsCredentialsKey &&
        _awsExpires != null &&
        DateTime.now().toUtc().isAfter(_awsExpires!)) {
      _cache.remove(key);
    }
    return _cache[key];
  }

  /// For tests.
  static void clear() {
    _cache.clear();
    _awsExpires = null;
    _refresh?.cancel();
    _refresh = null;
  }

  /// The console URL, or null.
  static String? consoleUrl({
    Map<String, String>? environment,
    String? home,
    String? cwd,
  }) {
    final env = environment ?? Platform.environment;
    final fromEnv = env['PODSHIP_CONSOLE_URL'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    String? fromYaml(String path) {
      final f = File(path);
      if (!f.existsSync()) return null;
      try {
        final y = loadYaml(f.readAsStringSync());
        final c = y is Map ? y['console'] : null;
        final u = c is Map ? c['url'] : null;
        return u is String && u.isNotEmpty ? u : null;
      } on Object {
        return null;
      }
    }

    final h = home ?? env['HOME'] ?? '.';
    return fromYaml(p.join(h, '.podship', 'config.yaml')) ??
        fromYaml(p.join(cwd ?? Directory.current.path, 'podship.yaml'));
  }

  /// Fetches the credentials of [providers] from the console. Returns the
  /// providers it got. A missing console or token gives nothing (the
  /// Keychain stays the fallback); [warn] gets a short reason, never a value.
  static Future<Set<String>> prime({
    Set<String> providers = const {'cloudflare', 'aws'},
    String? url,
    String? token,
    void Function(String)? warn,
    HttpClient Function()? client,
  }) async {
    final u = url ?? consoleUrl();
    if (u == null) return {};
    final t = token ?? TokenStore().readStored(u);
    if (t == null || t.isEmpty) {
      warn?.call('no token for $u: run `podship login $u`');
      return {};
    }
    final got = <String>{};
    for (final provider in providers) {
      try {
        final j = await _get(u, t, provider, client: client);
        if (j == null) continue;
        if (provider == 'cloudflare' && j['token'] is String) {
          _cache[cloudflareTokenKey] = j['token'] as String;
          got.add(provider);
        } else if (provider == 'aws' && j['access_key_id'] is String) {
          _cache[awsCredentialsKey] = AwsCredentials(
            j['access_key_id'] as String,
            j['secret_access_key'] as String,
            sessionToken: j['session_token'] as String?,
          ).toJson();
          final exp = DateTime.tryParse('${j['expiration']}');
          // Refresh 5 minutes before the STS credentials end.
          _awsExpires = exp?.toUtc().subtract(const Duration(minutes: 5));
          got.add(provider);
        }
      } on Object catch (e) {
        warn?.call('the console did not give $provider credentials ($e)');
      }
    }
    return got;
  }

  /// For long-running processes (the watch): fetches the AWS credentials
  /// again every 40 minutes, so they never expire.
  static void keepFresh({
    String? url,
    String? token,
    void Function(String)? warn,
  }) {
    _refresh?.cancel();
    _refresh = Timer.periodic(
      const Duration(minutes: 40),
      (_) =>
          prime(providers: const {'aws'}, url: url, token: token, warn: warn),
    );
  }

  static Future<Map?> _get(
    String url,
    String token,
    String provider, {
    HttpClient Function()? client,
  }) async {
    final c = (client ?? HttpClient.new)()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final base = url.endsWith('/') ? url : '$url/';
      final req = await c.getUrl(
        // The CLI's AWS work (email setup, email sender) needs the full
        // role; the console gives send-only credentials by default.
        Uri.parse(
          '${base}podship/v1/integrations/$provider/credentials'
          '${provider == 'aws' ? '?scope=full' : ''}',
        ),
      );
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      // 409: the provider is not connected.
      if (res.statusCode == 409 || res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final j = jsonDecode(body);
      return j is Map ? j : null;
    } finally {
      c.close(force: true);
    }
  }
}
