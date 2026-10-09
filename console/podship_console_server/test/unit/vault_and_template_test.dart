import 'dart:convert';
import 'dart:io';

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
    final t = jsonDecode(AwsTemplate.build()) as Map;
    final r = t['Resources'] as Map;

    test('trusts the issuer and the workspace subject from parameters', () {
      final role = r['PodshipRole']['Properties'] as Map;
      final trust = role['AssumeRolePolicyDocument']['Fn::Sub'] as String;
      // After Fn::Sub it must be valid JSON with the expected conditions.
      final filled = trust
          .replaceAll(
            r'${PodshipOidcProvider}',
            'arn:aws:iam::1:oidc-provider/x',
          )
          .replaceAll(r'${IssuerHost}', 'podship.example.com')
          .replaceAll(r'${Subject}', 'workspace:acme');
      final st = (jsonDecode(filled)['Statement'] as List).single;
      expect(st['Action'], 'sts:AssumeRoleWithWebIdentity');
      expect(st['Condition']['StringEquals'], {
        'podship.example.com:aud': 'sts.amazonaws.com',
        'podship.example.com:sub': 'workspace:acme',
      });
      expect(
        (t['Parameters'] as Map).keys,
        containsAll(['IssuerHost', 'Subject', 'ExternalId', 'CallbackUrl']),
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
      expect(
        sts.firstWhere((s) => s['Sid'] == 'KeepTheBoundary')['Effect'],
        'Deny',
      );
    });

    test('the committed file is the built template (console/aws/)', () {
      final file = File('../aws/connect-${AwsTemplate.version}.json');
      expect(file.readAsStringSync(), AwsTemplate.build());
    });

    test('the quick-create link fills every parameter', () {
      final u = AwsTemplate.quickCreateUrl(
        templateUrl:
            'https://podship-templates-1.s3.us-west-1.amazonaws.com/aws/connect-v1.json',
        region: 'us-west-1',
        issuerHost: 'podship.example.com',
        subject: 'workspace:acme',
        externalId: 'CODE123',
        callbackUrl: 'https://podship.example.com/integrations/aws/callback',
      );
      expect(
        u,
        startsWith(
          'https://us-west-1.console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks/create/review?',
        ),
      );
      final q = Uri.splitQueryString(u.split('#/stacks/create/review?').last);
      expect(q['stackName'], 'podship');
      expect(q['param_ExternalId'], 'CODE123');
      expect(q['param_IssuerHost'], 'podship.example.com');
      expect(q['param_Subject'], 'workspace:acme');
      expect(q['templateURL'], endsWith('/aws/connect-v1.json'));
    });
  });
}
