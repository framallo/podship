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

/// The template to download and the CloudFormation page to open (INT-11).
abstract class AwsStart
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  AwsStart._({
    required this.fileName,
    required this.template,
    required this.consoleUrl,
  });

  factory AwsStart({
    required String fileName,
    required String template,
    required String consoleUrl,
  }) = _AwsStartImpl;

  factory AwsStart.fromJson(Map<String, dynamic> jsonSerialization) {
    return AwsStart(
      fileName: jsonSerialization['fileName'] as String,
      template: jsonSerialization['template'] as String,
      consoleUrl: jsonSerialization['consoleUrl'] as String,
    );
  }

  String fileName;

  String template;

  String consoleUrl;

  /// Returns a shallow copy of this [AwsStart]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  AwsStart copyWith({
    String? fileName,
    String? template,
    String? consoleUrl,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AwsStart',
      'fileName': fileName,
      'template': template,
      'consoleUrl': consoleUrl,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AwsStart',
      'fileName': fileName,
      'template': template,
      'consoleUrl': consoleUrl,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _AwsStartImpl extends AwsStart {
  _AwsStartImpl({
    required String fileName,
    required String template,
    required String consoleUrl,
  }) : super._(
         fileName: fileName,
         template: template,
         consoleUrl: consoleUrl,
       );

  /// Returns a shallow copy of this [AwsStart]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  AwsStart copyWith({
    String? fileName,
    String? template,
    String? consoleUrl,
  }) {
    return AwsStart(
      fileName: fileName ?? this.fileName,
      template: template ?? this.template,
      consoleUrl: consoleUrl ?? this.consoleUrl,
    );
  }
}
