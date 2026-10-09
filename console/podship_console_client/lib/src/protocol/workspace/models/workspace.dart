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

/// A workspace: people and projects that share the provider integrations.
abstract class Workspace
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  Workspace._({
    this.id,
    required this.name,
    required this.slug,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Workspace({
    int? id,
    required String name,
    required String slug,
    DateTime? createdAt,
  }) = _WorkspaceImpl;

  factory Workspace.fromJson(Map<String, dynamic> jsonSerialization) {
    return Workspace(
      id: jsonSerialization['id'] as int?,
      name: jsonSerialization['name'] as String,
      slug: jsonSerialization['slug'] as String,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _isc.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String name;

  /// URL-safe name, for example `density-labs`.
  String slug;

  DateTime createdAt;

  /// Returns a shallow copy of this [Workspace]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  Workspace copyWith({
    int? id,
    String? name,
    String? slug,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Workspace',
      if (id != null) 'id': id,
      'name': name,
      'slug': slug,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Workspace',
      if (id != null) 'id': id,
      'name': name,
      'slug': slug,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _WorkspaceImpl extends Workspace {
  _WorkspaceImpl({
    int? id,
    required String name,
    required String slug,
    DateTime? createdAt,
  }) : super._(
         id: id,
         name: name,
         slug: slug,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [Workspace]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  Workspace copyWith({
    Object? id = _Undefined,
    String? name,
    String? slug,
    DateTime? createdAt,
  }) {
    return Workspace(
      id: id is int? ? id : this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
