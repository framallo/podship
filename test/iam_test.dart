@Tags(['unit'])
library;

import 'dart:convert';

import 'package:podship/src/integrations/http.dart';
import 'package:podship/src/integrations/iam.dart';
import 'package:podship/src/integrations/secrets.dart';
import 'package:test/test.dart';

const _caller = '''
<GetCallerIdentityResponse><GetCallerIdentityResult>
<Arn>arn:aws:sts::123456789012:assumed-role/podship-console/s</Arn>
<UserId>AROA:s</UserId><Account>123456789012</Account>
</GetCallerIdentityResult></GetCallerIdentityResponse>''';

String _keys(List<String> ids) =>
    '<ListAccessKeysResponse><ListAccessKeysResult><AccessKeyMetadata>'
    '${ids.map((i) => '<member><AccessKeyId>$i</AccessKeyId></member>').join()}'
    '</AccessKeyMetadata></ListAccessKeysResult></ListAccessKeysResponse>';

const _newKey = '''
<CreateAccessKeyResponse><CreateAccessKeyResult><AccessKey>
<AccessKeyId>AKIANEW</AccessKeyId><SecretAccessKey>s3cr3t</SecretAccessKey>
</AccessKey></CreateAccessKeyResult></CreateAccessKeyResponse>''';

/// Routes the Query API by its `Action`.
class QueryTransport implements HttpTransport {
  QueryTransport(this.answers);
  final Map<String, HttpReply Function(Map<String, String>)> answers;
  final List<Map<String, String>> calls = [];

  @override
  Future<HttpReply> send(HttpCall call) async {
    final p = Uri.splitQueryString(call.body ?? '');
    calls.add(p);
    expect(call.headers['Authorization'], startsWith('AWS4-HMAC-SHA256'));
    expect(call.headers['X-Amz-Security-Token'], 'session');
    final f = answers[p['Action']];
    if (f == null) throw StateError('no answer for ${p['Action']}');
    return f(p);
  }
}

HttpReply _ok(String xml) => HttpReply(200, xml);
HttpReply _err(int status, String code) => HttpReply(
  status,
  '<ErrorResponse><Error><Code>$code</Code><Message>m</Message></Error></ErrorResponse>',
);

final _creds = AwsCredentials('ASIA', 'secret', sessionToken: 'session');

void main() {
  test(
    'a new sender gets the path, the boundary, the send-only policy and a key',
    () async {
      final t = QueryTransport({
        'GetCallerIdentity': (_) => _ok(_caller),
        // A role limited to /podship-ses/ sees AccessDenied for a missing user.
        'GetUser': (_) => _err(403, 'AccessDenied'),
        'CreateUser': (_) => _ok('<CreateUserResponse/>'),
        'PutUserPolicy': (_) => _ok('<PutUserPolicyResponse/>'),
        'ListAccessKeys': (_) => _ok(_keys([])),
        'CreateAccessKey': (_) => _ok(_newKey),
      });
      final r = await IamApi(_creds, transport: t).ensureSender(
        name: 'presente-ses',
        region: 'us-west-1',
        identity: 'presente.densitylabs.io',
        project: 'presente/staging',
      );
      expect(r.created, isTrue);
      expect(r.key.accessKeyId, 'AKIANEW');
      final create = t.calls.firstWhere((c) => c['Action'] == 'CreateUser');
      expect(create['Path'], '/podship-ses/');
      expect(
        create['PermissionsBoundary'],
        'arn:aws:iam::123456789012:policy/podship-ses-sender',
      );
      final policy = jsonDecode(
        t.calls.firstWhere(
          (c) => c['Action'] == 'PutUserPolicy',
        )['PolicyDocument']!,
      );
      final st = (policy['Statement'] as List).single;
      expect(st['Action'], ['ses:SendEmail', 'ses:SendRawEmail']);
      expect(
        st['Resource'],
        contains(
          'arn:aws:ses:us-west-1:123456789012:identity/presente.densitylabs.io',
        ),
      );
    },
  );

  test('2 keys without --rotate: refuses and makes no key', () async {
    final t = QueryTransport({
      'GetCallerIdentity': (_) => _ok(_caller),
      'GetUser': (_) => _ok('<GetUserResponse/>'),
      'PutUserPolicy': (_) => _ok('<PutUserPolicyResponse/>'),
      'ListAccessKeys': (_) => _ok(_keys(['AKIA1', 'AKIA2'])),
    });
    await expectLater(
      IamApi(_creds, transport: t).ensureSender(
        name: 'presente-ses',
        region: 'us-west-1',
        identity: 'presente.densitylabs.io',
        project: 'presente/staging',
      ),
      throwsA(isA<IamException>()),
    );
    expect(t.calls.where((c) => c['Action'] == 'CreateAccessKey'), isEmpty);
  });

  test('rotate: the new key exists before the old ones go', () async {
    final t = QueryTransport({
      'GetCallerIdentity': (_) => _ok(_caller),
      'GetUser': (_) => _ok('<GetUserResponse/>'),
      'PutUserPolicy': (_) => _ok('<PutUserPolicyResponse/>'),
      'ListAccessKeys': (_) => _ok(_keys(['AKIA1'])),
      'CreateAccessKey': (_) => _ok(_newKey),
      'DeleteAccessKey': (_) => _ok('<DeleteAccessKeyResponse/>'),
    });
    final r = await IamApi(_creds, transport: t).ensureSender(
      name: 'presente-ses',
      region: 'us-west-1',
      identity: 'presente.densitylabs.io',
      project: 'presente/staging',
      rotate: true,
    );
    expect(r.created, isFalse);
    expect(r.deleted, ['AKIA1']);
    final order = [for (final c in t.calls) c['Action']];
    expect(
      order.indexOf('CreateAccessKey'),
      lessThan(order.indexOf('DeleteAccessKey')),
    );
  });
}
