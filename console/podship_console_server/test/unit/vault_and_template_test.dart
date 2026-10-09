import 'dart:convert';

import 'package:podship_console_server/src/core/secrets.dart';
import 'package:podship_console_server/src/core/vault.dart';
import 'package:podship_console_server/src/integrations/aws_template.dart';
import 'package:test/test.dart';

void main() {
  group('Vault (INT-4)', () {
    final vault = Vault(List.generate(32, (i) => i));

    test('a value decrypts with its own aad only', () async {
      final c = await vault.encrypt(
        'secret-token',
        aad: 'integration:1:cloudflare',
      );
      expect(c, isNot(contains('secret-token')));
      expect(
        await vault.decrypt(c, aad: 'integration:1:cloudflare'),
        'secret-token',
      );
      expect(
        () => vault.decrypt(c, aad: 'integration:2:cloudflare'),
        throwsA(anything),
      );
    });

    test('two encryptions of one value differ (random nonce)', () async {
      final a = await vault.encrypt('x', aad: 'a');
      final b = await vault.encrypt('x', aad: 'a');
      expect(a, isNot(b));
    });
  });

  test('hint shows the last 4 characters only (INT-5)', () {
    expect(Secrets.hint('abcdefgh1234'), '…1234');
    expect(Secrets.hint('abc'), '');
  });

  group('AWS template', () {
    final t =
        jsonDecode(
              AwsTemplate.build(
                issuerUrl: 'https://podship.example.com',
                subject: 'workspace:acme',
                callbackUrl:
                    'https://podship.example.com/integrations/aws/callback',
                code: 'ONE-TIME-CODE',
                workspace: 'Acme',
              ),
            )
            as Map;
    final r = t['Resources'] as Map;

    test('trusts only the console issuer and the workspace subject', () {
      final role = r['PodshipRole']['Properties'] as Map;
      final st = (role['AssumeRolePolicyDocument']['Statement'] as List).single;
      expect(st['Action'], 'sts:AssumeRoleWithWebIdentity');
      expect(st['Condition']['StringEquals'], {
        'podship.example.com:aud': 'sts.amazonaws.com',
        'podship.example.com:sub': 'workspace:acme',
      });
      expect(
        r['PodshipOidcProvider']['Properties']['Url'],
        'https://podship.example.com',
      );
    });

    test('makes no access key and no IAM user', () {
      for (final res in r.values) {
        expect(res['Type'], isNot('AWS::IAM::AccessKey'));
        expect(res['Type'], isNot('AWS::IAM::User'));
      }
    });

    test('sending users must carry the send-only boundary', () {
      final policy =
          (r['PodshipRole']['Properties']['Policies'] as List).single;
      final sts = policy['PolicyDocument']['Statement'] as List;
      final create = sts.firstWhere((s) => s['Sid'] == 'CreateSendingUsers');
      expect(create['Condition']['StringEquals']['iam:PermissionsBoundary'], {
        'Ref': 'PodshipSenderBoundary',
      });
      final boundary =
          r['PodshipSenderBoundary']['Properties']['PolicyDocument']['Statement']
              as List;
      expect(boundary.single['Action'], ['ses:SendEmail', 'ses:SendRawEmail']);
      final deny = sts.firstWhere((s) => s['Sid'] == 'KeepTheBoundary');
      expect(deny['Effect'], 'Deny');
    });

    test('the callback carries the one-time code', () {
      final code =
          r['PodshipCallback']['Properties']['Code']['ZipFile'] as String;
      expect(code, contains('"ONE-TIME-CODE"'));
      expect(code, contains('/integrations/aws/callback'));
    });
  });
}
