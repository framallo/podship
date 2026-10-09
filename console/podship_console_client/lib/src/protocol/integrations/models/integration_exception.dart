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
import '../../integrations/models/integration_failure.dart' as _i314gghq;

/// Why a connect failed. `detail` names a permission or a cause, never a
/// secret.
abstract class IntegrationException
    implements
        _isc.SerializableException,
        _isc.SerializableModel,
        _isc.ProtocolSerialization {
  IntegrationException._({
    required this.reason,
    this.detail,
  });

  factory IntegrationException({
    required _i314gghq.IntegrationFailure reason,
    String? detail,
  }) = _IntegrationExceptionImpl;

  factory IntegrationException.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return IntegrationException(
      reason: _i314gghq.IntegrationFailure.fromJson(
        (jsonSerialization['reason'] as String),
      ),
      detail: jsonSerialization['detail'] as String?,
    );
  }

  _i314gghq.IntegrationFailure reason;

  String? detail;

  /// Returns a shallow copy of this [IntegrationException]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  IntegrationException copyWith({
    _i314gghq.IntegrationFailure? reason,
    String? detail,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'IntegrationException',
      'reason': reason.toJson(),
      if (detail != null) 'detail': detail,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'IntegrationException',
      'reason': reason.toJson(),
      if (detail != null) 'detail': detail,
    };
  }

  @override
  String toString() {
    return 'IntegrationException(reason: $reason, detail: $detail)';
  }
}

class _Undefined {}

class _IntegrationExceptionImpl extends IntegrationException {
  _IntegrationExceptionImpl({
    required _i314gghq.IntegrationFailure reason,
    String? detail,
  }) : super._(
         reason: reason,
         detail: detail,
       );

  /// Returns a shallow copy of this [IntegrationException]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  IntegrationException copyWith({
    _i314gghq.IntegrationFailure? reason,
    Object? detail = _Undefined,
  }) {
    return IntegrationException(
      reason: reason ?? this.reason,
      detail: detail is String? ? detail : this.detail,
    );
  }
}
