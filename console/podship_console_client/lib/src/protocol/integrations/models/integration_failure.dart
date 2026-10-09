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

enum IntegrationFailure implements _isc.SerializableModel {
  forbidden,
  empty,
  invalid,
  inactive,
  missingPermission,
  unreachable,

  /// The AWS template is not published yet (CONSOLE_AWS_TEMPLATE_URL).
  notReady;

  static IntegrationFailure fromJson(String name) {
    switch (name) {
      case 'forbidden':
        return IntegrationFailure.forbidden;
      case 'empty':
        return IntegrationFailure.empty;
      case 'invalid':
        return IntegrationFailure.invalid;
      case 'inactive':
        return IntegrationFailure.inactive;
      case 'missingPermission':
        return IntegrationFailure.missingPermission;
      case 'unreachable':
        return IntegrationFailure.unreachable;
      case 'notReady':
        return IntegrationFailure.notReady;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "IntegrationFailure"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
