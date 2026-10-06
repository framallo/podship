// Transports: where an operation runs.
//
// `ssh`: in this process; podship talks to the servers over ssh.
// `console`: a podship console runs it on its side, with its own deploy
// key, and streams the events back. Both give the same events.
//
// The console API (protocol version 1):
//   POST <console>/podship/v1/operations   body: OperationRequest JSON
//        Authorization: Bearer <token>      answer: NDJSON of EventEnvelope
//   GET  <console>/podship/v1/whoami        answer: {"user":…, "roles":{…}}
//   GET  <console>/podship/v1/operations    answer: the operation catalog

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/podship.dart';
import 'protocol.dart';

/// The console did not answer.
class ConsoleUnreachable implements Exception {
  ConsoleUnreachable(this.url, this.cause);
  final String url;
  final Object cause;
  @override
  String toString() => 'the console at $url does not answer ($cause)';
}

/// The console refused the request.
class ConsoleRefused implements Exception {
  ConsoleRefused(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => status == 401
      ? 'the console does not accept your token: run `podship login <console-url>`'
      : status == 403
      ? 'the console does not allow this for your role: $message'
      : 'the console answered $status: $message';
}

abstract class Transport {
  /// The events of [req] as JSON maps, ending with a `result` event.
  Stream<Map<String, Object?>> run(OperationRequest req);
}

/// Runs operations here, over ssh.
class SshTransport implements Transport {
  SshTransport(this.podship);
  final Podship podship;
  @override
  Stream<Map<String, Object?>> run(OperationRequest req) =>
      dispatch(podship, req);
}

/// Sends operations to a console.
class ConsoleTransport implements Transport {
  ConsoleTransport(this.url, this.token);
  final String url;
  final String token;

  Uri _uri(String path) =>
      Uri.parse(url.endsWith('/') ? '$url$path' : '$url/$path');

  Future<HttpClientResponse> _send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, _uri(path));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(
          HttpHeaders.acceptHeader,
          'application/x-ndjson, application/json',
        );
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      if (res.statusCode >= 400) {
        final text = await res.transform(utf8.decoder).join();
        throw ConsoleRefused(res.statusCode, text.trim());
      }
      return res;
    } on SocketException catch (e) {
      throw ConsoleUnreachable(url, e.message);
    } on HandshakeException catch (e) {
      throw ConsoleUnreachable(url, e.message);
    } on TimeoutException catch (e) {
      throw ConsoleUnreachable(url, e);
    }
  }

  @override
  Stream<Map<String, Object?>> run(OperationRequest req) async* {
    final res = await _send('POST', 'podship/v1/operations', req.toJson());
    await for (final line
        in res.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line) as Map<String, Object?>;
      final e = (j['event'] as Map?)?.cast<String, Object?>() ?? j;
      yield e;
    }
  }

  /// Who the token belongs to, and the roles.
  Future<Map<String, Object?>> whoami() async {
    final res = await _send('GET', 'podship/v1/whoami');
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, Object?>;
  }
}
