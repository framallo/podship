import 'dart:convert';

import 'package:crypto/crypto.dart';
// ignore: implementation_imports
import 'package:podship/src/integrations/sigv4.dart' show signV4;
import 'package:podship/podship.dart'
    show AwsCredentials, HttpCall, HttpTransport;

/// Uploads the connect template to its S3 object (S3 PutObject, SigV4).
class TemplateStore {
  TemplateStore(this._http);
  final HttpTransport _http;

  Future<void> put(
    Uri url,
    String body,
    AwsCredentials creds, {
    required String region,
  }) async {
    final hash = sha256.convert(utf8.encode(body)).toString();
    final signed = signV4(
      HttpCall(
        'PUT',
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-amz-content-sha256': hash,
        },
        body: body,
      ),
      creds,
      region: region,
      service: 's3',
      doubleEncodePath: false,
    ).call;
    final r = await _http.send(signed);
    if (r.status >= 300) {
      final code = RegExp('<Code>([^<]*)</Code>').firstMatch(r.body)?[1];
      throw StateError('S3 PUT ${url.path}: ${r.status} ${code ?? ''}');
    }
  }
}
