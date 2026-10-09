import 'package:podship/podship.dart'
    show AwsCredentials, HttpCall, HttpTransport, IoTransport;

/// Temporary AWS credentials from STS.
class StsCredentials {
  StsCredentials(this.credentials, this.expiration);
  final AwsCredentials credentials;
  final DateTime expiration;
}

/// The STS error, without the token.
class StsError implements Exception {
  StsError(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => 'STS $status $code: $message';
}

/// `AssumeRoleWithWebIdentity`. The call carries no AWS signature: the web
/// identity token is the proof, so no AWS key exists anywhere.
class Sts {
  Sts({HttpTransport? transport, this.region = 'us-west-1'})
    : _http = transport ?? IoTransport();
  final HttpTransport _http;
  final String region;

  static String? _tag(String xml, String name) =>
      RegExp('<$name>([^<]*)</$name>').firstMatch(xml)?.group(1);

  Future<StsCredentials> assumeRoleWithWebIdentity({
    required String roleArn,
    required String token,
    required String sessionName,
    int durationSeconds = 3600,
  }) async {
    final body = Uri(
      queryParameters: {
        'Action': 'AssumeRoleWithWebIdentity',
        'Version': '2011-06-15',
        'RoleArn': roleArn,
        'RoleSessionName': sessionName,
        'WebIdentityToken': token,
        'DurationSeconds': '$durationSeconds',
      },
    ).query;
    final reply = await _http.send(
      HttpCall(
        'POST',
        Uri.parse('https://sts.$region.amazonaws.com/'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      ),
    );
    if (reply.status != 200) {
      throw StsError(
        reply.status,
        _tag(reply.body, 'Code') ?? 'Error',
        _tag(reply.body, 'Message') ?? '',
      );
    }
    final id = _tag(reply.body, 'AccessKeyId');
    final secret = _tag(reply.body, 'SecretAccessKey');
    final session = _tag(reply.body, 'SessionToken');
    final exp = _tag(reply.body, 'Expiration');
    if (id == null || secret == null || session == null || exp == null) {
      throw StsError(reply.status, 'Malformed', 'no credentials in the answer');
    }
    return StsCredentials(
      AwsCredentials(id, secret, sessionToken: session),
      DateTime.parse(exp),
    );
  }
}
