// AWS Signature Version 4 for JSON/REST APIs (SES v2).
//
// https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html
// The unit tests check it against AWS's published test vectors.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'http.dart';
import 'secrets.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _hmac(List<int> key, String data) =>
    Hmac(sha256, key).convert(utf8.encode(data)).bytes;

/// RFC 3986 encoding: everything but unreserved characters.
String awsEncode(String s, {bool keepSlash = false}) {
  final b = StringBuffer();
  for (final byte in utf8.encode(s)) {
    final c = String.fromCharCode(byte);
    if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(c) || (keepSlash && c == '/')) {
      b.write(c);
    } else {
      b.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return b.toString();
}

/// `20150830T123600Z`.
String amzDate(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// The parts of a signature, for tests and debugging (no secret in them).
class SigV4Parts {
  SigV4Parts(this.canonicalRequest, this.stringToSign, this.authorization);
  final String canonicalRequest;
  final String stringToSign;
  final String authorization;
}

/// Signs [call] for [service] in [region]. Returns the call with the
/// `Authorization`, `X-Amz-Date` (and session token) headers added.
/// [doubleEncodePath] is true for every service but S3.
({HttpCall call, SigV4Parts parts}) signV4(
  HttpCall call,
  AwsCredentials creds, {
  required String region,
  required String service,
  DateTime? now,
  bool doubleEncodePath = true,
}) {
  final date = amzDate(now ?? DateTime.now());
  final day = date.substring(0, 8);
  final headers = <String, String>{
    ...call.headers,
    'Host': call.url.hasPort && call.url.port != 443 && call.url.port != 80
        ? '${call.url.host}:${call.url.port}'
        : call.url.host,
    'X-Amz-Date': date,
    'X-Amz-Security-Token': ?creds.sessionToken,
  };
  final canonicalHeaders = <String, String>{
    for (final h in headers.entries)
      h.key.toLowerCase(): h.value.trim().replaceAll(RegExp(r'\s+'), ' '),
  };
  final names = canonicalHeaders.keys.toList()..sort();
  final signedHeaders = names.join(';');
  final path = call.url.path.isEmpty ? '/' : call.url.path;
  final canonicalUri = doubleEncodePath
      ? awsEncode(path, keepSlash: true)
      : path;
  final query = [
    for (final e in call.url.queryParametersAll.entries)
      for (final v in e.value) '${awsEncode(e.key)}=${awsEncode(v)}',
  ]..sort();
  final payloadHash = _hex(sha256.convert(utf8.encode(call.body ?? '')).bytes);
  final canonicalRequest = [
    call.method,
    canonicalUri,
    query.join('&'),
    for (final n in names) '$n:${canonicalHeaders[n]}',
    '',
    signedHeaders,
    payloadHash,
  ].join('\n');
  final scope = '$day/$region/$service/aws4_request';
  final stringToSign = [
    'AWS4-HMAC-SHA256',
    date,
    scope,
    _hex(sha256.convert(utf8.encode(canonicalRequest)).bytes),
  ].join('\n');
  var key = _hmac(utf8.encode('AWS4${creds.secretAccessKey}'), day);
  key = _hmac(key, region);
  key = _hmac(key, service);
  key = _hmac(key, 'aws4_request');
  final signature = _hex(_hmac(key, stringToSign));
  final authorization =
      'AWS4-HMAC-SHA256 Credential=${creds.accessKeyId}/$scope, '
      'SignedHeaders=$signedHeaders, Signature=$signature';
  return (
    call: HttpCall(
      call.method,
      call.url,
      headers: {...headers, 'Authorization': authorization},
      body: call.body,
    ),
    parts: SigV4Parts(canonicalRequest, stringToSign, authorization),
  );
}
