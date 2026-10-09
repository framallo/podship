// Per-app SES sending users (`<project>-ses`), made by podship through the
// workspace's AWS integration (podship-design: decisions/
// 2026-10-09-integrations-phase-1). The console's role may only make users
// under `/podship-ses/` that carry the boundary `podship-ses-sender`
// (send email only). Each user gets an inline policy that allows sending
// from its own SES identity only.
//
// IAM and STS speak the AWS Query API (form POST, XML answers). Nothing here
// logs a request or a key.

import 'dart:convert';

import 'http.dart';
import 'secrets.dart';
import 'sigv4.dart';

class IamException implements Exception {
  IamException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  bool get notFound => code == 'NoSuchEntity';
  @override
  String toString() => 'IAM $status $code: $message';
}

/// An access key, shown once.
class IamAccessKey {
  IamAccessKey(this.accessKeyId, this.secretAccessKey);
  final String accessKeyId;
  final String secretAccessKey;
}

class IamApi {
  IamApi(this._creds, {HttpTransport? transport, DateTime Function()? clock})
    : transport = transport ?? IoTransport(),
      _clock = clock ?? DateTime.now;
  final AwsCredentials _creds;
  final HttpTransport transport;
  final DateTime Function() _clock;

  static const path = '/podship-ses/';
  static const boundaryName = 'podship-ses-sender';

  static String? tag(String xml, String name) =>
      RegExp('<$name>([^<]*)</$name>').firstMatch(xml)?.group(1);

  static List<String> tags(String xml, String name) => [
    for (final m in RegExp('<$name>([^<]*)</$name>').allMatches(xml)) m[1]!,
  ];

  Future<String> _call(
    String service,
    String host,
    String region,
    String version,
    Map<String, String> params,
  ) async {
    final body = Uri(queryParameters: {...params, 'Version': version}).query;
    final signed = signV4(
      HttpCall(
        'POST',
        Uri.parse('https://$host/'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: body,
      ),
      _creds,
      region: region,
      service: service,
      now: _clock(),
    ).call;
    final r = await transport.send(signed);
    if (r.status >= 400) {
      throw IamException(
        r.status,
        tag(r.body, 'Code') ?? 'Error',
        tag(r.body, 'Message') ?? '${params['Action']} failed',
      );
    }
    return r.body;
  }

  Future<String> _iam(Map<String, String> p) =>
      _call('iam', 'iam.amazonaws.com', 'us-east-1', '2010-05-08', p);

  /// The 12-digit account of the credentials.
  Future<String> accountId() async {
    final xml = await _call(
      'sts',
      'sts.amazonaws.com',
      'us-east-1',
      '2011-06-15',
      {'Action': 'GetCallerIdentity'},
    );
    final a = tag(xml, 'Account');
    if (a == null) throw IamException(200, 'Malformed', 'no Account');
    return a;
  }

  /// True when the user exists.
  Future<bool> userExists(String name) async {
    try {
      await _iam({'Action': 'GetUser', 'UserName': name});
      return true;
    } on IamException catch (e) {
      // IAM checks a missing user against `user/<name>` without the path, so
      // a role limited to `/podship-ses/` gets AccessDenied instead of
      // NoSuchEntity. CreateUser then answers EntityAlreadyExists when the
      // name is taken elsewhere.
      if (e.notFound || e.code == 'AccessDenied') return false;
      rethrow;
    }
  }

  Future<void> createUser(
    String name, {
    required String boundaryArn,
    Map<String, String> tags = const {},
  }) async {
    final p = <String, String>{
      'Action': 'CreateUser',
      'UserName': name,
      'Path': path,
      'PermissionsBoundary': boundaryArn,
    };
    var i = 1;
    for (final t in tags.entries) {
      p['Tags.member.$i.Key'] = t.key;
      p['Tags.member.$i.Value'] = t.value;
      i++;
    }
    await _iam(p);
  }

  Future<void> putUserPolicy(
    String user,
    String policyName,
    Map<String, Object?> document,
  ) => _iam({
    'Action': 'PutUserPolicy',
    'UserName': user,
    'PolicyName': policyName,
    'PolicyDocument': jsonEncode(document),
  });

  Future<List<String>> accessKeyIds(String user) async => tags(
    await _iam({'Action': 'ListAccessKeys', 'UserName': user}),
    'AccessKeyId',
  );

  Future<IamAccessKey> createAccessKey(String user) async {
    final xml = await _iam({'Action': 'CreateAccessKey', 'UserName': user});
    final id = tag(xml, 'AccessKeyId');
    final secret = tag(xml, 'SecretAccessKey');
    if (id == null || secret == null) {
      throw IamException(200, 'Malformed', 'no access key in the answer');
    }
    return IamAccessKey(id, secret);
  }

  Future<void> deleteAccessKey(String user, String id) =>
      _iam({'Action': 'DeleteAccessKey', 'UserName': user, 'AccessKeyId': id});

  /// The send-only policy of a per-app user: SendEmail and SendRawEmail from
  /// [identity] in [region] only.
  static Map<String, Object?> sendPolicy({
    required String account,
    required String region,
    required String identity,
  }) => {
    'Version': '2012-10-17',
    'Statement': [
      {
        'Effect': 'Allow',
        'Action': ['ses:SendEmail', 'ses:SendRawEmail'],
        'Resource': [
          'arn:aws:ses:$region:$account:identity/$identity',
          'arn:aws:ses:$region:$account:configuration-set/*',
        ],
      },
    ],
  };

  /// Makes (or keeps) the user `<name>` with the boundary and the send-only
  /// policy, then a new access key. With [rotate], older keys are deleted
  /// after the new one exists. IAM allows 2 keys per user: without
  /// [rotate] and with 2 keys, this refuses.
  Future<({IamAccessKey key, bool created, List<String> deleted})>
  ensureSender({
    required String name,
    required String region,
    required String identity,
    required String project,
    bool rotate = false,
  }) async {
    final account = await accountId();
    final boundary = 'arn:aws:iam::$account:policy/$boundaryName';
    var created = false;
    if (!await userExists(name)) {
      await createUser(
        name,
        boundaryArn: boundary,
        tags: {'podship': project, 'podship-identity': identity},
      );
      created = true;
    }
    await putUserPolicy(
      name,
      'ses-send-$identity',
      sendPolicy(account: account, region: region, identity: identity),
    );
    final old = await accessKeyIds(name);
    if (old.length >= 2 && !rotate) {
      throw IamException(
        409,
        'LimitExceeded',
        '$name has 2 access keys: pass --rotate to replace them',
      );
    }
    if (rotate && old.length >= 2) {
      // Make room for the new key: the oldest goes first.
      await deleteAccessKey(name, old.first);
      old.removeAt(0);
    }
    final key = await createAccessKey(name);
    final deleted = <String>[];
    if (rotate) {
      for (final id in old) {
        await deleteAccessKey(name, id);
        deleted.add(id);
      }
    }
    return (key: key, created: created, deleted: deleted);
  }
}
