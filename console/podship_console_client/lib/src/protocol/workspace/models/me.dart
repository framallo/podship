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
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import '../../workspace/models/workspace_role.dart' as _iwddgb3z;

/// What the app knows about the signed-in person.
abstract class Me
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  Me._({
    required this.email,
    required this.workspaceId,
    required this.workspaceName,
    required this.role,
    required this.canManage,
    required this.locale,
  });

  factory Me({
    required String email,
    required int workspaceId,
    required String workspaceName,
    required _iwddgb3z.WorkspaceRole role,
    required bool canManage,
    required String locale,
  }) = _MeImpl;

  factory Me.fromJson(Map<String, dynamic> jsonSerialization) {
    return Me(
      email: jsonSerialization['email'] as String,
      workspaceId: jsonSerialization['workspaceId'] as int,
      workspaceName: jsonSerialization['workspaceName'] as String,
      role: _iwddgb3z.WorkspaceRole.fromJson(
        (jsonSerialization['role'] as String),
      ),
      canManage: _isc.BoolJsonExtension.fromJson(
        jsonSerialization['canManage'],
      ),
      locale: jsonSerialization['locale'] as String,
    );
  }

  String email;

  int workspaceId;

  String workspaceName;

  _iwddgb3z.WorkspaceRole role;

  /// Owners and admins may connect and disconnect (INT-3).
  bool canManage;

  String locale;

  /// Returns a shallow copy of this [Me]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  Me copyWith({
    String? email,
    int? workspaceId,
    String? workspaceName,
    _iwddgb3z.WorkspaceRole? role,
    bool? canManage,
    String? locale,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Me',
      'email': email,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'role': role.toJson(),
      'canManage': canManage,
      'locale': locale,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Me',
      'email': email,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'role': role.toJson(),
      'canManage': canManage,
      'locale': locale,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _MeImpl extends Me {
  _MeImpl({
    required String email,
    required int workspaceId,
    required String workspaceName,
    required _iwddgb3z.WorkspaceRole role,
    required bool canManage,
    required String locale,
  }) : super._(
         email: email,
         workspaceId: workspaceId,
         workspaceName: workspaceName,
         role: role,
         canManage: canManage,
         locale: locale,
       );

  /// Returns a shallow copy of this [Me]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  Me copyWith({
    String? email,
    int? workspaceId,
    String? workspaceName,
    _iwddgb3z.WorkspaceRole? role,
    bool? canManage,
    String? locale,
  }) {
    return Me(
      email: email ?? this.email,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceName: workspaceName ?? this.workspaceName,
      role: role ?? this.role,
      canManage: canManage ?? this.canManage,
      locale: locale ?? this.locale,
    );
  }
}
