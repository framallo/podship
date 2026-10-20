// The project's issue tracker: where a suite that failed after the switch
// opens an issue. One tracker today, Boceto, over its HTTP API
// (`POST /api/v1/tools/create_issue` with a `bct_…` bearer token). The
// token comes from the secret store (`tracker:boceto`, or BOCETO_TOKEN in
// the environment), never from podship.yaml.
import 'dart:convert';

import 'http.dart';

class IssuesException implements Exception {
  IssuesException(this.message);
  final String message;
  @override
  String toString() => 'issues: $message';
}

/// An issue the tracker made.
class CreatedIssue {
  CreatedIssue({required this.number, required this.url});
  final int number;
  final String url;
}

/// Boceto's tracker over its HTTP API.
class BocetoIssues {
  BocetoIssues({
    required String url,
    required this.project,
    required this.token,
    HttpTransport? transport,
  }) : url = url.replaceAll(RegExp(r'/+$'), ''),
       transport = transport ?? IoTransport();

  final String url;
  final String project;
  final String token;
  final HttpTransport transport;

  /// Opens an issue with [title] and [body] (Markdown), labelled for
  /// triage, and returns its number and URL.
  Future<CreatedIssue> create({
    required String title,
    required String body,
  }) async {
    final reply = await transport.send(
      HttpCall(
        'POST',
        Uri.parse('$url/api/v1/tools/create_issue'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'project': project,
          'title': title,
          'description': body,
          'labels': ['needs-triage'],
        }),
      ),
    );
    final json = reply.body.isEmpty ? null : _json(reply.body);
    if (reply.status < 200 || reply.status >= 300) {
      final message = json is Map ? json['message'] ?? json['error'] : null;
      throw IssuesException(
        'create_issue answered ${reply.status}${message == null ? '' : ': $message'}',
      );
    }
    if (json is! Map || json['number'] is! num) {
      throw IssuesException('create_issue answered without an issue number');
    }
    return CreatedIssue(
      number: (json['number'] as num).toInt(),
      url: '${json['url'] ?? '$url/issues/${json['number']}'}',
    );
  }

  static Object? _json(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
