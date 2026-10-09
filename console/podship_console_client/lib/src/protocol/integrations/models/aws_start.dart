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

/// The CloudFormation quick-create link to open (INT-11): template,
/// stack name and every parameter filled in.
abstract class AwsStart
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  AwsStart._({required this.consoleUrl});

  factory AwsStart({required String consoleUrl}) = _AwsStartImpl;

  factory AwsStart.fromJson(Map<String, dynamic> jsonSerialization) {
    return AwsStart(consoleUrl: jsonSerialization['consoleUrl'] as String);
  }

  String consoleUrl;

  /// Returns a shallow copy of this [AwsStart]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  AwsStart copyWith({String? consoleUrl});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AwsStart',
      'consoleUrl': consoleUrl,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AwsStart',
      'consoleUrl': consoleUrl,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _AwsStartImpl extends AwsStart {
  _AwsStartImpl({required String consoleUrl}) : super._(consoleUrl: consoleUrl);

  /// Returns a shallow copy of this [AwsStart]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  AwsStart copyWith({String? consoleUrl}) {
    return AwsStart(consoleUrl: consoleUrl ?? this.consoleUrl);
  }
}
