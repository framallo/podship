/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: dead_code, unnecessary_type_check

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:podship_console_server/src/generated/integrations/models/integration_view.dart'
    as _ivjnvw04;
import 'package:serverpod/protocol.dart' as _isp;
import 'package:serverpod/serverpod.dart' as _is;
import 'package:serverpod_auth_core_server/serverpod_auth_core_server.dart'
    as _iacs;
import 'package:serverpod_auth_idp_server/serverpod_auth_idp_server.dart'
    as _iais;
import 'auth/models/email_code.dart' as _iy4lnptb;
import 'auth/models/email_code_exception.dart' as _iukg966n;
import 'auth/models/email_code_failure.dart' as _ivtcuv76;
import 'auth/models/email_code_request.dart' as _i4z3lx3e;
import 'auth/models/sign_in_link.dart' as _i6pq04kz;
import 'auth/models/sign_in_link_created.dart' as _i4hzc5me;
import 'integrations/models/aws_connect_request.dart' as _ibnvoxr0;
import 'integrations/models/aws_start.dart' as _i497qpsg;
import 'integrations/models/integration.dart' as _ioqu486n;
import 'integrations/models/integration_audit.dart' as _igjnorwf;
import 'integrations/models/integration_exception.dart' as _ih3eloay;
import 'integrations/models/integration_failure.dart' as _iaqu3qvt;
import 'integrations/models/integration_view.dart' as _id63l5cj;
import 'integrations/models/oidc_key.dart' as _ivt3uw2e;
import 'integrations/models/provider.dart' as _idapvel8;
import 'tokens/models/access_token.dart' as _ie95idqn;
import 'workspace/models/me.dart' as _i9zmvvje;
import 'workspace/models/workspace.dart' as _i1dy1q9g;
import 'workspace/models/workspace_member.dart' as _i0hu2dgt;
import 'workspace/models/workspace_role.dart' as _iv8ll4gl;
export 'auth/models/email_code.dart';
export 'auth/models/email_code_exception.dart';
export 'auth/models/email_code_failure.dart';
export 'auth/models/email_code_request.dart';
export 'auth/models/sign_in_link.dart';
export 'auth/models/sign_in_link_created.dart';
export 'integrations/models/aws_connect_request.dart';
export 'integrations/models/aws_start.dart';
export 'integrations/models/integration.dart';
export 'integrations/models/integration_audit.dart';
export 'integrations/models/integration_exception.dart';
export 'integrations/models/integration_failure.dart';
export 'integrations/models/integration_view.dart';
export 'integrations/models/oidc_key.dart';
export 'integrations/models/provider.dart';
export 'tokens/models/access_token.dart';
export 'workspace/models/me.dart';
export 'workspace/models/workspace.dart';
export 'workspace/models/workspace_member.dart';
export 'workspace/models/workspace_role.dart';

class Protocol extends _is.DatabaseSerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._().._registerHostProtocols();

  static List<_isp.TableDefinition> get targetTableDefinitions => [
    _isp.TableDefinition(
      name: 'access_token',
      dartName: 'AccessToken',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'email',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'name',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'tokenHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
        _isp.ColumnDefinition(
          name: 'expiresAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'lastUsedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'revokedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'access_token_hash_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'tokenHash',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'aws_connect_request',
      dartName: 'AwsConnectRequest',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'codeHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdBy',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
        _isp.ColumnDefinition(
          name: 'expiresAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'usedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'aws_connect_code_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'codeHash',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'email_code_account',
      dartName: 'EmailCodeAccount',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'random_v7',
        ),
        _isp.ColumnDefinition(
          name: 'authUserId',
          columnType: _isp.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _isp.ColumnDefinition(
          name: 'email',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'locale',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'en\'',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
        _isp.ColumnDefinition(
          name: 'lastLoginAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'email_code_account_fk_0',
          columns: ['authUserId'],
          referenceTable: 'serverpod_auth_core_user',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.cascade,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'email_code_account_email_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'email',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'email_code_request',
      dartName: 'EmailCodeRequest',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'random_v7',
        ),
        _isp.ColumnDefinition(
          name: 'email',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'codeHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'expiresAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'attempts',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'consumedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'locale',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'en\'',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'email_code_request_email_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'email',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'integration',
      dartName: 'Integration',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'provider',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:IntegrationProvider',
        ),
        _isp.ColumnDefinition(
          name: 'status',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'secret',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'hint',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'details',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'{}\'',
        ),
        _isp.ColumnDefinition(
          name: 'connectedBy',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'connectedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'lastCheckAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'lastCheckOk',
          columnType: _isp.ColumnType.boolean,
          isNullable: true,
          dartType: 'bool?',
        ),
        _isp.ColumnDefinition(
          name: 'lastError',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'updatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'integration_fk_0',
          columns: ['workspaceId'],
          referenceTable: 'workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.cascade,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'integration_workspace_provider_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'workspaceId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'provider',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'integration_audit',
      dartName: 'IntegrationAudit',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'provider',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:IntegrationProvider',
        ),
        _isp.ColumnDefinition(
          name: 'action',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'actor',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'ok',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _isp.ColumnDefinition(
          name: 'detail',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
          columnDefault: '\'\'',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'integration_audit_ws_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'workspaceId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'createdAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'oidc_key',
      dartName: 'OidcKey',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'kid',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'privateKey',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'publicJwk',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
        _isp.ColumnDefinition(
          name: 'retiredAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'oidc_key_kid_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'kid',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'sign_in_link',
      dartName: 'SignInLink',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue?',
          columnDefault: 'random_v7',
        ),
        _isp.ColumnDefinition(
          name: 'email',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'tokenHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'expiresAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'consumedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'sign_in_link_token_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'tokenHash',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'workspace',
      dartName: 'Workspace',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'name',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'slug',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'workspace_slug_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'slug',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'workspace_member',
      dartName: 'WorkspaceMember',
      schema: 'public',
      module: 'podship_console',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'email',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'role',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:WorkspaceRole',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
          columnDefault: 'now',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'workspace_member_fk_0',
          columns: ['workspaceId'],
          referenceTable: 'workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.cascade,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'workspace_member_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'workspaceId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'email',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    ..._iais.Protocol.targetTableDefinitions,
    ..._iacs.Protocol.targetTableDefinitions,
    ..._isp.Protocol.targetTableDefinitions,
  ];

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on _is.DeserializationClassNameNotFoundException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _iy4lnptb.EmailCodeAccount) {
      return _iy4lnptb.EmailCodeAccount.fromJson(data) as T;
    }
    if (t == _iukg966n.EmailCodeException) {
      return _iukg966n.EmailCodeException.fromJson(data) as T;
    }
    if (t == _ivtcuv76.EmailCodeFailure) {
      return _ivtcuv76.EmailCodeFailure.fromJson(data) as T;
    }
    if (t == _i4z3lx3e.EmailCodeRequest) {
      return _i4z3lx3e.EmailCodeRequest.fromJson(data) as T;
    }
    if (t == _i6pq04kz.SignInLink) {
      return _i6pq04kz.SignInLink.fromJson(data) as T;
    }
    if (t == _i4hzc5me.SignInLinkCreated) {
      return _i4hzc5me.SignInLinkCreated.fromJson(data) as T;
    }
    if (t == _ibnvoxr0.AwsConnectRequest) {
      return _ibnvoxr0.AwsConnectRequest.fromJson(data) as T;
    }
    if (t == _i497qpsg.AwsStart) {
      return _i497qpsg.AwsStart.fromJson(data) as T;
    }
    if (t == _ioqu486n.Integration) {
      return _ioqu486n.Integration.fromJson(data) as T;
    }
    if (t == _igjnorwf.IntegrationAudit) {
      return _igjnorwf.IntegrationAudit.fromJson(data) as T;
    }
    if (t == _ih3eloay.IntegrationException) {
      return _ih3eloay.IntegrationException.fromJson(data) as T;
    }
    if (t == _iaqu3qvt.IntegrationFailure) {
      return _iaqu3qvt.IntegrationFailure.fromJson(data) as T;
    }
    if (t == _id63l5cj.IntegrationView) {
      return _id63l5cj.IntegrationView.fromJson(data) as T;
    }
    if (t == _ivt3uw2e.OidcKey) {
      return _ivt3uw2e.OidcKey.fromJson(data) as T;
    }
    if (t == _idapvel8.IntegrationProvider) {
      return _idapvel8.IntegrationProvider.fromJson(data) as T;
    }
    if (t == _ie95idqn.AccessToken) {
      return _ie95idqn.AccessToken.fromJson(data) as T;
    }
    if (t == _i9zmvvje.Me) {
      return _i9zmvvje.Me.fromJson(data) as T;
    }
    if (t == _i1dy1q9g.Workspace) {
      return _i1dy1q9g.Workspace.fromJson(data) as T;
    }
    if (t == _i0hu2dgt.WorkspaceMember) {
      return _i0hu2dgt.WorkspaceMember.fromJson(data) as T;
    }
    if (t == _iv8ll4gl.WorkspaceRole) {
      return _iv8ll4gl.WorkspaceRole.fromJson(data) as T;
    }
    if (t == _is.getType<_iy4lnptb.EmailCodeAccount?>()) {
      return (data != null ? _iy4lnptb.EmailCodeAccount.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_iukg966n.EmailCodeException?>()) {
      return (data != null ? _iukg966n.EmailCodeException.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ivtcuv76.EmailCodeFailure?>()) {
      return (data != null ? _ivtcuv76.EmailCodeFailure.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i4z3lx3e.EmailCodeRequest?>()) {
      return (data != null ? _i4z3lx3e.EmailCodeRequest.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i6pq04kz.SignInLink?>()) {
      return (data != null ? _i6pq04kz.SignInLink.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i4hzc5me.SignInLinkCreated?>()) {
      return (data != null ? _i4hzc5me.SignInLinkCreated.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ibnvoxr0.AwsConnectRequest?>()) {
      return (data != null ? _ibnvoxr0.AwsConnectRequest.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i497qpsg.AwsStart?>()) {
      return (data != null ? _i497qpsg.AwsStart.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ioqu486n.Integration?>()) {
      return (data != null ? _ioqu486n.Integration.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_igjnorwf.IntegrationAudit?>()) {
      return (data != null ? _igjnorwf.IntegrationAudit.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ih3eloay.IntegrationException?>()) {
      return (data != null
              ? _ih3eloay.IntegrationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _is.getType<_iaqu3qvt.IntegrationFailure?>()) {
      return (data != null ? _iaqu3qvt.IntegrationFailure.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_id63l5cj.IntegrationView?>()) {
      return (data != null ? _id63l5cj.IntegrationView.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ivt3uw2e.OidcKey?>()) {
      return (data != null ? _ivt3uw2e.OidcKey.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_idapvel8.IntegrationProvider?>()) {
      return (data != null
              ? _idapvel8.IntegrationProvider.fromJson(data)
              : null)
          as T;
    }
    if (t == _is.getType<_ie95idqn.AccessToken?>()) {
      return (data != null ? _ie95idqn.AccessToken.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i9zmvvje.Me?>()) {
      return (data != null ? _i9zmvvje.Me.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i1dy1q9g.Workspace?>()) {
      return (data != null ? _i1dy1q9g.Workspace.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i0hu2dgt.WorkspaceMember?>()) {
      return (data != null ? _i0hu2dgt.WorkspaceMember.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_iv8ll4gl.WorkspaceRole?>()) {
      return (data != null ? _iv8ll4gl.WorkspaceRole.fromJson(data) : null)
          as T;
    }
    if (t == List<_ivjnvw04.IntegrationView>) {
      return (data as List)
              .map((e) => deserialize<_ivjnvw04.IntegrationView>(e))
              .toList()
          as T;
    }
    try {
      return _iais.Protocol().deserialize<T>(data, t);
    } on _is.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _iacs.Protocol().deserialize<T>(data, t);
    } on _is.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _isp.Protocol().deserialize<T>(data, t);
    } on _is.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _iy4lnptb.EmailCodeAccount => 'EmailCodeAccount',
      _iukg966n.EmailCodeException => 'EmailCodeException',
      _ivtcuv76.EmailCodeFailure => 'EmailCodeFailure',
      _i4z3lx3e.EmailCodeRequest => 'EmailCodeRequest',
      _i6pq04kz.SignInLink => 'SignInLink',
      _i4hzc5me.SignInLinkCreated => 'SignInLinkCreated',
      _ibnvoxr0.AwsConnectRequest => 'AwsConnectRequest',
      _i497qpsg.AwsStart => 'AwsStart',
      _ioqu486n.Integration => 'Integration',
      _igjnorwf.IntegrationAudit => 'IntegrationAudit',
      _ih3eloay.IntegrationException => 'IntegrationException',
      _iaqu3qvt.IntegrationFailure => 'IntegrationFailure',
      _id63l5cj.IntegrationView => 'IntegrationView',
      _ivt3uw2e.OidcKey => 'OidcKey',
      _idapvel8.IntegrationProvider => 'IntegrationProvider',
      _ie95idqn.AccessToken => 'AccessToken',
      _i9zmvvje.Me => 'Me',
      _i1dy1q9g.Workspace => 'Workspace',
      _i0hu2dgt.WorkspaceMember => 'WorkspaceMember',
      _iv8ll4gl.WorkspaceRole => 'WorkspaceRole',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst(
        'podship_console.',
        '',
      );
    }

    switch (data) {
      case _iy4lnptb.EmailCodeAccount():
        return 'EmailCodeAccount';
      case _iukg966n.EmailCodeException():
        return 'EmailCodeException';
      case _ivtcuv76.EmailCodeFailure():
        return 'EmailCodeFailure';
      case _i4z3lx3e.EmailCodeRequest():
        return 'EmailCodeRequest';
      case _i6pq04kz.SignInLink():
        return 'SignInLink';
      case _i4hzc5me.SignInLinkCreated():
        return 'SignInLinkCreated';
      case _ibnvoxr0.AwsConnectRequest():
        return 'AwsConnectRequest';
      case _i497qpsg.AwsStart():
        return 'AwsStart';
      case _ioqu486n.Integration():
        return 'Integration';
      case _igjnorwf.IntegrationAudit():
        return 'IntegrationAudit';
      case _ih3eloay.IntegrationException():
        return 'IntegrationException';
      case _iaqu3qvt.IntegrationFailure():
        return 'IntegrationFailure';
      case _id63l5cj.IntegrationView():
        return 'IntegrationView';
      case _ivt3uw2e.OidcKey():
        return 'OidcKey';
      case _idapvel8.IntegrationProvider():
        return 'IntegrationProvider';
      case _ie95idqn.AccessToken():
        return 'AccessToken';
      case _i9zmvvje.Me():
        return 'Me';
      case _i1dy1q9g.Workspace():
        return 'Workspace';
      case _i0hu2dgt.WorkspaceMember():
        return 'WorkspaceMember';
      case _iv8ll4gl.WorkspaceRole():
        return 'WorkspaceRole';
    }
    className = _iais.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_idp.$className';
    }
    className = _iacs.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_core.$className';
    }
    className = _isp.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.') ? className : 'serverpod.$className';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'EmailCodeAccount') {
      return deserialize<_iy4lnptb.EmailCodeAccount>(data['data']);
    }
    if (dataClassName == 'EmailCodeException') {
      return deserialize<_iukg966n.EmailCodeException>(data['data']);
    }
    if (dataClassName == 'EmailCodeFailure') {
      return deserialize<_ivtcuv76.EmailCodeFailure>(data['data']);
    }
    if (dataClassName == 'EmailCodeRequest') {
      return deserialize<_i4z3lx3e.EmailCodeRequest>(data['data']);
    }
    if (dataClassName == 'SignInLink') {
      return deserialize<_i6pq04kz.SignInLink>(data['data']);
    }
    if (dataClassName == 'SignInLinkCreated') {
      return deserialize<_i4hzc5me.SignInLinkCreated>(data['data']);
    }
    if (dataClassName == 'AwsConnectRequest') {
      return deserialize<_ibnvoxr0.AwsConnectRequest>(data['data']);
    }
    if (dataClassName == 'AwsStart') {
      return deserialize<_i497qpsg.AwsStart>(data['data']);
    }
    if (dataClassName == 'Integration') {
      return deserialize<_ioqu486n.Integration>(data['data']);
    }
    if (dataClassName == 'IntegrationAudit') {
      return deserialize<_igjnorwf.IntegrationAudit>(data['data']);
    }
    if (dataClassName == 'IntegrationException') {
      return deserialize<_ih3eloay.IntegrationException>(data['data']);
    }
    if (dataClassName == 'IntegrationFailure') {
      return deserialize<_iaqu3qvt.IntegrationFailure>(data['data']);
    }
    if (dataClassName == 'IntegrationView') {
      return deserialize<_id63l5cj.IntegrationView>(data['data']);
    }
    if (dataClassName == 'OidcKey') {
      return deserialize<_ivt3uw2e.OidcKey>(data['data']);
    }
    if (dataClassName == 'IntegrationProvider') {
      return deserialize<_idapvel8.IntegrationProvider>(data['data']);
    }
    if (dataClassName == 'AccessToken') {
      return deserialize<_ie95idqn.AccessToken>(data['data']);
    }
    if (dataClassName == 'Me') {
      return deserialize<_i9zmvvje.Me>(data['data']);
    }
    if (dataClassName == 'Workspace') {
      return deserialize<_i1dy1q9g.Workspace>(data['data']);
    }
    if (dataClassName == 'WorkspaceMember') {
      return deserialize<_i0hu2dgt.WorkspaceMember>(data['data']);
    }
    if (dataClassName == 'WorkspaceRole') {
      return deserialize<_iv8ll4gl.WorkspaceRole>(data['data']);
    }
    if (dataClassName.startsWith('serverpod_auth_idp.')) {
      data['className'] = dataClassName.substring(19);
      return _iais.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _iacs.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod.')) {
      data['className'] = dataClassName.substring(10);
      return _isp.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  void _registerHostProtocols() {
    _iais.Protocol().registerHostProtocol('podship_console', this);
    _iacs.Protocol().registerHostProtocol('podship_console', this);
  }

  @override
  _is.Table? getTableForType(Type t) {
    {
      var table = _iais.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    {
      var table = _iacs.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    {
      var table = _isp.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    switch (t) {
      case _iy4lnptb.EmailCodeAccount:
        return _iy4lnptb.EmailCodeAccount.t;
      case _i4z3lx3e.EmailCodeRequest:
        return _i4z3lx3e.EmailCodeRequest.t;
      case _i6pq04kz.SignInLink:
        return _i6pq04kz.SignInLink.t;
      case _ibnvoxr0.AwsConnectRequest:
        return _ibnvoxr0.AwsConnectRequest.t;
      case _ioqu486n.Integration:
        return _ioqu486n.Integration.t;
      case _igjnorwf.IntegrationAudit:
        return _igjnorwf.IntegrationAudit.t;
      case _ivt3uw2e.OidcKey:
        return _ivt3uw2e.OidcKey.t;
      case _ie95idqn.AccessToken:
        return _ie95idqn.AccessToken.t;
      case _i1dy1q9g.Workspace:
        return _i1dy1q9g.Workspace.t;
      case _i0hu2dgt.WorkspaceMember:
        return _i0hu2dgt.WorkspaceMember.t;
    }
    return null;
  }

  @override
  List<_isp.TableDefinition> getTargetTableDefinitions() =>
      targetTableDefinitions;

  @override
  String getModuleName() => 'podship_console';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    try {
      return _iais.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _iacs.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
