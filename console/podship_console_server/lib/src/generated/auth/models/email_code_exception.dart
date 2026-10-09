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
import '../../auth/models/email_code_failure.dart' as _isbf3bot;

/// Error while requesting or redeeming a sign-in code or link.
abstract class EmailCodeException
    implements
        _is.SerializableException,
        _is.SerializableModel,
        _is.ProtocolSerialization {
  EmailCodeException._({required this.reason});

  factory EmailCodeException({required _isbf3bot.EmailCodeFailure reason}) =
      _EmailCodeExceptionImpl;

  factory EmailCodeException.fromJson(Map<String, dynamic> jsonSerialization) {
    return EmailCodeException(
      reason: _isbf3bot.EmailCodeFailure.fromJson(
        (jsonSerialization['reason'] as String),
      ),
    );
  }

  _isbf3bot.EmailCodeFailure reason;

  /// Returns a shallow copy of this [EmailCodeException]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  EmailCodeException copyWith({_isbf3bot.EmailCodeFailure? reason});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EmailCodeException',
      'reason': reason.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'EmailCodeException',
      'reason': reason.toJson(),
    };
  }

  @override
  String toString() {
    return 'EmailCodeException(reason: $reason)';
  }
}

class _EmailCodeExceptionImpl extends EmailCodeException {
  _EmailCodeExceptionImpl({required _isbf3bot.EmailCodeFailure reason})
    : super._(reason: reason);

  /// Returns a shallow copy of this [EmailCodeException]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  EmailCodeException copyWith({_isbf3bot.EmailCodeFailure? reason}) {
    return EmailCodeException(reason: reason ?? this.reason);
  }
}
