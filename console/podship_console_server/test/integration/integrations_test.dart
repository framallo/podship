import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' hide Padding, State;
import 'package:podship/podship.dart' show Fixture, FixtureTransport, jsonReply;
import 'package:podship_console_server/src/core/app_config.dart';
import 'package:podship_console_server/src/generated/protocol.dart';
import 'package:podship_console_server/src/integrations/integration_service.dart';
import 'package:podship_console_server/src/integrations/oidc.dart';
import 'package:podship_console_server/src/workspace/workspace_service.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const _token = 'cf-token-abcdefghijklmnopqrstuvwxyz-9f1a';

FixtureTransport _cloudflare({bool tunnels = true}) => FixtureTransport([
  Fixture(
    'GET',
    '/client/v4/user/tokens/verify',
    jsonReply({
      'success': true,
      'result': {'id': 't1', 'status': 'active'},
    }),
  ),
  Fixture(
    'GET',
    '/client/v4/zones',
    jsonReply({
      'success': true,
      'result': [
        {
          'id': 'z1',
          'name': 'example.com',
          'status': 'active',
          'account': {'id': 'acc1', 'name': 'Acme'},
        },
      ],
      'result_info': {'total_pages': 1},
    }),
  ),
  Fixture(
    'GET',
    '/client/v4/zones/z1/dns_records',
    jsonReply({
      'success': true,
      'result': [],
      'result_info': {'total_pages': 1},
    }),
  ),
  Fixture(
    'GET',
    '/client/v4/accounts/acc1/cfd_tunnel',
    tunnels
        ? jsonReply({
            'success': true,
            'result': [],
            'result_info': {'total_pages': 1},
          })
        : jsonReply({
            'success': false,
            'errors': [
              {'code': 10000, 'message': 'Authentication error'},
            ],
          }, status: 403),
  ),
  Fixture(
    'GET',
    '/client/v4/accounts/acc1/access/apps',
    jsonReply({
      'success': true,
      'result': [],
      'result_info': {'total_pages': 1},
    }),
  ),
  Fixture(
    'GET',
    '/client/v4/accounts/acc1',
    jsonReply({
      'success': true,
      'result': {'id': 'acc1', 'name': 'Acme'},
    }),
  ),
]);

void main() {
  AppConfig.forTest(
    key: List.generate(32, (i) => 255 - i),
    ownerEmails: {'owner@example.com'},
  );

  withServerpod('Integrations', (sessionBuilder, endpoints) {
    Future<Actor> actor(String email, WorkspaceRole? role) async {
      final s = sessionBuilder.build();
      final ws = await WorkspaceService.ensure(s);
      if (role != null && role != WorkspaceRole.owner) {
        await WorkspaceMember.db.insertRow(
          s,
          WorkspaceMember(workspaceId: ws.id!, email: email, role: role),
        );
      }
      return Actor(
        email: email,
        workspace: ws,
        role: role ?? WorkspaceRole.owner,
      );
    }

    test(
      'an owner connects Cloudflare; the row holds no clear token',
      () async {
        IntegrationService.deps = IntegrationDeps(transport: _cloudflare());
        final s = sessionBuilder.build();
        final a = await actor('owner@example.com', WorkspaceRole.owner);
        final v = await IntegrationService.saveCloudflare(s, a, '  $_token  ');
        expect(v.status, 'connected');
        expect(v.hint, '…9f1a');
        expect(v.account, 'Acme');
        expect(v.zones, 1);
        final row = (await Integration.db.find(s)).single;
        expect(row.secret, isNot(contains(_token)));
        expect(jsonEncode(row.toJson()), isNot(contains(_token)));
        final audit = await IntegrationAudit.db.find(s);
        expect(audit.map((r) => r.action), contains('connect'));
        for (final r in audit) {
          expect(r.detail, isNot(contains(_token)));
        }
      },
    );

    test(
      'a missing permission is named and nothing is stored (INT-9)',
      () async {
        IntegrationService.deps = IntegrationDeps(
          transport: _cloudflare(tunnels: false),
        );
        final s = sessionBuilder.build();
        final a = await actor('owner@example.com', WorkspaceRole.owner);
        await expectLater(
          IntegrationService.saveCloudflare(s, a, _token),
          throwsA(
            isA<IntegrationException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  IntegrationFailure.missingPermission,
                )
                .having((e) => e.detail, 'detail', 'argotunnel:edit'),
          ),
        );
        expect(await Integration.db.count(s), 0);
        final audit = await IntegrationAudit.db.find(s);
        expect(audit.single.action, 'connect_refused');
      },
    );

    test(
      'a member cannot connect, disconnect or read credentials (INT-3)',
      () async {
        IntegrationService.deps = IntegrationDeps(transport: _cloudflare());
        final s = sessionBuilder.build();
        final m = await actor('member@example.com', WorkspaceRole.member);
        final forbidden = throwsA(
          isA<IntegrationException>().having(
            (e) => e.reason,
            'reason',
            IntegrationFailure.forbidden,
          ),
        );
        await expectLater(
          IntegrationService.saveCloudflare(s, m, _token),
          forbidden,
        );
        await expectLater(IntegrationService.startAws(s, m), forbidden);
        await expectLater(
          IntegrationService.disconnect(s, m, IntegrationProvider.cloudflare),
          forbidden,
        );
        await expectLater(
          IntegrationService.credentialsFor(
            s,
            m,
            IntegrationProvider.cloudflare,
          ),
          forbidden,
        );
        // Members still see the status.
        expect((await IntegrationService.list(s, m)).length, 2);
      },
    );

    test(
      'an admin reads the Cloudflare token for the CLI, with an audit row',
      () async {
        IntegrationService.deps = IntegrationDeps(transport: _cloudflare());
        final s = sessionBuilder.build();
        final o = await actor('owner@example.com', WorkspaceRole.owner);
        await IntegrationService.saveCloudflare(s, o, _token);
        final admin = await actor('admin@example.com', WorkspaceRole.admin);
        final c = await IntegrationService.credentialsFor(
          s,
          admin,
          IntegrationProvider.cloudflare,
        );
        expect(c['token'], _token);
        final reads = await IntegrationAudit.db.find(
          s,
          where: (t) => t.action.equals('credential_read'),
        );
        expect(reads.single.actor, 'admin@example.com');
      },
    );

    test('disconnect deletes the credential (INT-16)', () async {
      IntegrationService.deps = IntegrationDeps(transport: _cloudflare());
      final s = sessionBuilder.build();
      final o = await actor('owner@example.com', WorkspaceRole.owner);
      await IntegrationService.saveCloudflare(s, o, _token);
      final v = await IntegrationService.disconnect(
        s,
        o,
        IntegrationProvider.cloudflare,
      );
      expect(v.status, 'off');
      expect(await Integration.db.count(s), 0);
    });

    test('the AWS callback refuses an unknown code (INT-12)', () async {
      final s = sessionBuilder.build();
      expect(
        await IntegrationService.awsCallback(s, {
          'code': 'nope',
          'request_type': 'Create',
          'role_arn': 'arn:aws:iam::123456789012:role/podship-console',
        }),
        isFalse,
      );
    });

    test(
      'startAws makes a template with a one-time code and a pending row',
      () async {
        final s = sessionBuilder.build();
        final o = await actor('owner@example.com', WorkspaceRole.owner);
        final start = await IntegrationService.startAws(s, o);
        expect(start.fileName, endsWith('.json'));
        final zip =
            (jsonDecode(start.template)
                    as Map)['Resources']['PodshipCallback']['Properties']['Code']['ZipFile']
                as String;
        final code = RegExp(r'CODE = "([A-Za-z0-9]+)"').firstMatch(zip)![1]!;
        final views = await IntegrationService.list(s, o);
        expect(
          views.firstWhere((v) => v.provider == IntegrationProvider.aws).status,
          'pending',
        );
        // A used code works once; a Delete with the code disconnects.
        expect(
          await IntegrationService.awsCallback(s, {
            'code': code,
            'request_type': 'Delete',
            'stack_id': 'stack-1',
          }),
          isTrue,
        );
        expect(await Integration.db.count(s), 0);
      },
    );

    test(
      'tokens are RS256 with the published key; rotate changes it',
      () async {
        final s = sessionBuilder.build();
        final jwt = await Oidc.sign(s, 'workspace:test');
        final parts = jwt.split('.');
        final header = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
        );
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        expect(header['alg'], 'RS256');
        expect(claims['aud'], 'sts.amazonaws.com');
        expect(claims['iss'], 'https://console.test');
        final jwks = await Oidc.jwks(s);
        final jwk = (jwks['keys'] as List).single as Map;
        expect(jwk['kid'], header['kid']);
        // AWS verifies the signature with the published key: so must we.
        BigInt big(String b64) {
          final bytes = base64Url.decode(base64Url.normalize(b64));
          return BigInt.parse(
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
            radix: 16,
          );
        }

        final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
          ..init(
            false,
            PublicKeyParameter<RSAPublicKey>(
              RSAPublicKey(big(jwk['n'] as String), big(jwk['e'] as String)),
            ),
          );
        final sig = base64Url.decode(base64Url.normalize(parts[2]));
        expect(
          verifier.verifySignature(
            Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
            RSASignature(sig),
          ),
          isTrue,
        );
        await Oidc.rotate(s);
        final after = await Oidc.jwks(s);
        expect((after['keys'] as List).single['kid'], isNot(header['kid']));
      },
    );
  });
}
