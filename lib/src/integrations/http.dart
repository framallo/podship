// HTTP for the API integrations (Cloudflare, AWS SES), behind one small
// interface so tests and plans never touch the network:
//
// - [IoTransport] sends real requests.
// - [ReadOnlyTransport] wraps another transport and refuses anything but
//   GET. Plans run on it, so computing a plan can never change anything.
// - [FixtureTransport] answers from recorded responses and records every
//   request, for tests (and for a console's own tests).
//
// Requests may carry credentials in headers. Nothing here logs a request.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One HTTP request.
class HttpCall {
  HttpCall(this.method, this.url, {this.headers = const {}, this.body});
  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// The body as text (JSON for both APIs), or null.
  final String? body;

  /// The body parsed as JSON, or null.
  Object? get json => body == null || body!.isEmpty ? null : jsonDecode(body!);

  /// `METHOD /path?query`, without the host: what fixtures match on.
  String get key => '$method ${url.path}${url.hasQuery ? '?${url.query}' : ''}';

  @override
  String toString() => key;
}

/// One HTTP response.
class HttpReply {
  HttpReply(this.status, this.body, {this.headers = const {}});
  final int status;
  final String body;

  /// Header names in lower case.
  final Map<String, String> headers;
  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

abstract class HttpTransport {
  Future<HttpReply> send(HttpCall call);
}

/// Real HTTP with dart:io.
class IoTransport implements HttpTransport {
  IoTransport({this.timeout = const Duration(seconds: 30)});
  final Duration timeout;

  @override
  Future<HttpReply> send(HttpCall call) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(call.method, call.url);
      for (final h in call.headers.entries) {
        if (h.key.toLowerCase() == 'host') continue;
        req.headers.set(h.key, h.value, preserveHeaderCase: true);
      }
      if (call.body != null) {
        final bytes = utf8.encode(call.body!);
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(', '));
      return HttpReply(res.statusCode, text, headers: headers);
    } finally {
      client.close(force: true);
    }
  }
}

/// A change was attempted on a read-only transport.
class ReadOnlyViolation implements Exception {
  ReadOnlyViolation(this.call);
  final HttpCall call;
  @override
  String toString() =>
      'refused ${call.method} ${call.url.path}: planning is read-only';
}

/// Passes GET requests through and refuses everything else.
class ReadOnlyTransport implements HttpTransport {
  ReadOnlyTransport(this.inner);
  final HttpTransport inner;
  @override
  Future<HttpReply> send(HttpCall call) {
    if (call.method != 'GET') throw ReadOnlyViolation(call);
    return inner.send(call);
  }
}

/// A recorded answer for [FixtureTransport].
class Fixture {
  Fixture(this.method, this.path, this.reply, {this.query, this.times});

  /// Loads `{"status": 200, "headers": {…}, "body": {…}}` (or a bare JSON
  /// body) from a file, for fixtures recorded from the real API.
  factory Fixture.file(
    String method,
    String path,
    String file, {
    Map<String, String>? query,
    int? times,
  }) {
    final j = jsonDecode(File(file).readAsStringSync());
    final envelope =
        j is Map && j.containsKey('status') && j.containsKey('body');
    return Fixture(
      method,
      path,
      HttpReply(
        envelope ? (j['status'] as num).toInt() : 200,
        jsonEncode(envelope ? j['body'] : j),
        headers: envelope
            ? {
                for (final e in ((j['headers'] as Map?) ?? const {}).entries)
                  '${e.key}'.toLowerCase(): '${e.value}',
              }
            : const {},
      ),
      query: query,
      times: times,
    );
  }

  final String method;

  /// The path, exactly, or with `*` for one segment.
  final String path;

  /// Query parameters that must be present with these values.
  final Map<String, String>? query;
  final HttpReply reply;

  /// How many times it answers (null: always). Later fixtures for the same
  /// request take over, so a test can model state that changes.
  int? times;

  bool matches(HttpCall c) {
    if (c.method != method) return false;
    final want = path.split('/');
    final got = c.url.path.split('/');
    if (want.length != got.length) return false;
    for (var i = 0; i < want.length; i++) {
      if (want[i] != '*' &&
          want[i] != got[i] &&
          want[i] != Uri.decodeComponent(got[i])) {
        return false;
      }
    }
    for (final q in (query ?? const <String, String>{}).entries) {
      if (c.url.queryParameters[q.key] != q.value) return false;
    }
    return true;
  }
}

/// Answers from [fixtures] (the first match that has answers left) and
/// records every call in [calls]. An unknown request throws, naming it.
class FixtureTransport implements HttpTransport {
  FixtureTransport([List<Fixture>? fixtures]) : fixtures = fixtures ?? [];
  final List<Fixture> fixtures;
  final List<HttpCall> calls = [];

  void add(Fixture f) => fixtures.add(f);

  /// The calls that changed something (not GET).
  List<HttpCall> get writes => [
    for (final c in calls)
      if (c.method != 'GET') c,
  ];

  @override
  Future<HttpReply> send(HttpCall call) async {
    calls.add(call);
    for (final f in fixtures) {
      if ((f.times ?? 1) > 0 && f.matches(call)) {
        if (f.times != null) f.times = f.times! - 1;
        return f.reply;
      }
    }
    throw StateError('no fixture for ${call.key}');
  }
}

/// A JSON reply, for fixtures written inline.
HttpReply jsonReply(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => HttpReply(status, body == null ? '' : jsonEncode(body), headers: headers);
