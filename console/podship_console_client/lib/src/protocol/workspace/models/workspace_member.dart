/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:podship_console_client/src/protocol/protocol.dart' as _i19cyykw;
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import '../../workspace/models/workspace.dart' as _ikenbmzt;
import '../../workspace/models/workspace_role.dart' as _iwddgb3z;

abstract class WorkspaceMember
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  WorkspaceMember._({
    this.id,
    required this.workspaceId,
    this.workspace,
    required this.email,
    required this.role,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory WorkspaceMember({
    int? id,
    required int workspaceId,
    _ikenbmzt.Workspace? workspace,
    required String email,
    required _iwddgb3z.WorkspaceRole role,
    DateTime? createdAt,
  }) = _WorkspaceMemberImpl;

  factory WorkspaceMember.fromJson(Map<String, dynamic> jsonSerialization) {
    return WorkspaceMember(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      workspace: jsonSerialization['workspace'] == null
          ? null
          : _i19cyykw.Protocol().deserialize<_ikenbmzt.Workspace>(
              jsonSerialization['workspace'],
            ),
      email: jsonSerialization['email'] as String,
      role: _iwddgb3z.WorkspaceRole.fromJson(
        (jsonSerialization['role'] as String),
      ),
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _isc.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  int workspaceId;

  _ikenbmzt.Workspace? workspace;

  /// Lowercase email. The person signs in with it.
  String email;

  _iwddgb3z.WorkspaceRole role;

  DateTime createdAt;

  /// Returns a shallow copy of this [WorkspaceMember]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  WorkspaceMember copyWith({
    int? id,
    int? workspaceId,
    _ikenbmzt.Workspace? workspace,
    String? email,
    _iwddgb3z.WorkspaceRole? role,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'WorkspaceMember',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      if (workspace != null) 'workspace': workspace?.toJson(),
      'email': email,
      'role': role.toJson(),
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'WorkspaceMember',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      if (workspace != null) 'workspace': workspace?.toJsonForProtocol(),
      'email': email,
      'role': role.toJson(),
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _WorkspaceMemberImpl extends WorkspaceMember {
  _WorkspaceMemberImpl({
    int? id,
    required int workspaceId,
    _ikenbmzt.Workspace? workspace,
    required String email,
    required _iwddgb3z.WorkspaceRole role,
    DateTime? createdAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         workspace: workspace,
         email: email,
         role: role,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [WorkspaceMember]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  WorkspaceMember copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    Object? workspace = _Undefined,
    String? email,
    _iwddgb3z.WorkspaceRole? role,
    DateTime? createdAt,
  }) {
    return WorkspaceMember(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      workspace: workspace is _ikenbmzt.Workspace?
          ? workspace
          : this.workspace?.copyWith(),
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
