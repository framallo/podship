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
import 'package:serverpod/serverpod.dart' as _is;

abstract class SignInLinkCreated
    implements _is.SerializableModel, _is.ProtocolSerialization {
  SignInLinkCreated._({
    required this.email,
    required this.url,
    required this.expiresAt,
  });

  factory SignInLinkCreated({
    required String email,
    required String url,
    required DateTime expiresAt,
  }) = _SignInLinkCreatedImpl;

  factory SignInLinkCreated.fromJson(Map<String, dynamic> jsonSerialization) {
    return SignInLinkCreated(
      email: jsonSerialization['email'] as String,
      url: jsonSerialization['url'] as String,
      expiresAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
    );
  }

  String email;

  String url;

  DateTime expiresAt;

  /// Returns a shallow copy of this [SignInLinkCreated]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  SignInLinkCreated copyWith({
    String? email,
    String? url,
    DateTime? expiresAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SignInLinkCreated',
      'email': email,
      'url': url,
      'expiresAt': expiresAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _SignInLinkCreatedImpl extends SignInLinkCreated {
  _SignInLinkCreatedImpl({
    required String email,
    required String url,
    required DateTime expiresAt,
  }) : super._(
         email: email,
         url: url,
         expiresAt: expiresAt,
       );

  /// Returns a shallow copy of this [SignInLinkCreated]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  SignInLinkCreated copyWith({
    String? email,
    String? url,
    DateTime? expiresAt,
  }) {
    return SignInLinkCreated(
      email: email ?? this.email,
      url: url ?? this.url,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
