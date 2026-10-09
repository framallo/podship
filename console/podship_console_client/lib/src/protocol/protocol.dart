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
import 'package:podship_console_client/src/protocol/integrations/models/integration_view.dart'
    as _i11dr8ol;
import 'package:serverpod_auth_core_client/serverpod_auth_core_client.dart'
    as _iacc;
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart'
    as _iaic;
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import 'auth/models/email_code_exception.dart' as _iukg966n;
import 'auth/models/email_code_failure.dart' as _ivtcuv76;
import 'integrations/models/aws_start.dart' as _i497qpsg;
import 'integrations/models/integration_exception.dart' as _ih3eloay;
import 'integrations/models/integration_failure.dart' as _iaqu3qvt;
import 'integrations/models/integration_view.dart' as _id63l5cj;
import 'integrations/models/provider.dart' as _idapvel8;
import 'workspace/models/me.dart' as _i9zmvvje;
import 'workspace/models/workspace.dart' as _i1dy1q9g;
import 'workspace/models/workspace_member.dart' as _i0hu2dgt;
import 'workspace/models/workspace_role.dart' as _iv8ll4gl;
export 'auth/models/email_code_exception.dart';
export 'auth/models/email_code_failure.dart';
export 'integrations/models/aws_start.dart';
export 'integrations/models/integration_exception.dart';
export 'integrations/models/integration_failure.dart';
export 'integrations/models/integration_view.dart';
export 'integrations/models/provider.dart';
export 'workspace/models/me.dart';
export 'workspace/models/workspace.dart';
export 'workspace/models/workspace_member.dart';
export 'workspace/models/workspace_role.dart';
export 'client.dart';

class Protocol extends _isc.SerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._().._registerHostProtocols();

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
      } on _isc.DeserializationClassNameNotFoundException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _iukg966n.EmailCodeException) {
      return _iukg966n.EmailCodeException.fromJson(data) as T;
    }
    if (t == _ivtcuv76.EmailCodeFailure) {
      return _ivtcuv76.EmailCodeFailure.fromJson(data) as T;
    }
    if (t == _i497qpsg.AwsStart) {
      return _i497qpsg.AwsStart.fromJson(data) as T;
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
    if (t == _idapvel8.IntegrationProvider) {
      return _idapvel8.IntegrationProvider.fromJson(data) as T;
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
    if (t == _isc.getType<_iukg966n.EmailCodeException?>()) {
      return (data != null ? _iukg966n.EmailCodeException.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_ivtcuv76.EmailCodeFailure?>()) {
      return (data != null ? _ivtcuv76.EmailCodeFailure.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_i497qpsg.AwsStart?>()) {
      return (data != null ? _i497qpsg.AwsStart.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_ih3eloay.IntegrationException?>()) {
      return (data != null
              ? _ih3eloay.IntegrationException.fromJson(data)
              : null)
          as T;
    }
    if (t == _isc.getType<_iaqu3qvt.IntegrationFailure?>()) {
      return (data != null ? _iaqu3qvt.IntegrationFailure.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_id63l5cj.IntegrationView?>()) {
      return (data != null ? _id63l5cj.IntegrationView.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_idapvel8.IntegrationProvider?>()) {
      return (data != null
              ? _idapvel8.IntegrationProvider.fromJson(data)
              : null)
          as T;
    }
    if (t == _isc.getType<_i9zmvvje.Me?>()) {
      return (data != null ? _i9zmvvje.Me.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_i1dy1q9g.Workspace?>()) {
      return (data != null ? _i1dy1q9g.Workspace.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_i0hu2dgt.WorkspaceMember?>()) {
      return (data != null ? _i0hu2dgt.WorkspaceMember.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_iv8ll4gl.WorkspaceRole?>()) {
      return (data != null ? _iv8ll4gl.WorkspaceRole.fromJson(data) : null)
          as T;
    }
    if (t == List<_i11dr8ol.IntegrationView>) {
      return (data as List)
              .map((e) => deserialize<_i11dr8ol.IntegrationView>(e))
              .toList()
          as T;
    }
    try {
      return _iaic.Protocol().deserialize<T>(data, t);
    } on _isc.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _iacc.Protocol().deserialize<T>(data, t);
    } on _isc.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _iukg966n.EmailCodeException => 'EmailCodeException',
      _ivtcuv76.EmailCodeFailure => 'EmailCodeFailure',
      _i497qpsg.AwsStart => 'AwsStart',
      _ih3eloay.IntegrationException => 'IntegrationException',
      _iaqu3qvt.IntegrationFailure => 'IntegrationFailure',
      _id63l5cj.IntegrationView => 'IntegrationView',
      _idapvel8.IntegrationProvider => 'IntegrationProvider',
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
      case _iukg966n.EmailCodeException():
        return 'EmailCodeException';
      case _ivtcuv76.EmailCodeFailure():
        return 'EmailCodeFailure';
      case _i497qpsg.AwsStart():
        return 'AwsStart';
      case _ih3eloay.IntegrationException():
        return 'IntegrationException';
      case _iaqu3qvt.IntegrationFailure():
        return 'IntegrationFailure';
      case _id63l5cj.IntegrationView():
        return 'IntegrationView';
      case _idapvel8.IntegrationProvider():
        return 'IntegrationProvider';
      case _i9zmvvje.Me():
        return 'Me';
      case _i1dy1q9g.Workspace():
        return 'Workspace';
      case _i0hu2dgt.WorkspaceMember():
        return 'WorkspaceMember';
      case _iv8ll4gl.WorkspaceRole():
        return 'WorkspaceRole';
    }
    className = _iaic.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_idp.$className';
    }
    className = _iacc.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_core.$className';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'EmailCodeException') {
      return deserialize<_iukg966n.EmailCodeException>(data['data']);
    }
    if (dataClassName == 'EmailCodeFailure') {
      return deserialize<_ivtcuv76.EmailCodeFailure>(data['data']);
    }
    if (dataClassName == 'AwsStart') {
      return deserialize<_i497qpsg.AwsStart>(data['data']);
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
    if (dataClassName == 'IntegrationProvider') {
      return deserialize<_idapvel8.IntegrationProvider>(data['data']);
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
      return _iaic.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _iacc.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  void _registerHostProtocols() {
    _iaic.Protocol().registerHostProtocol('podship_console', this);
    _iacc.Protocol().registerHostProtocol('podship_console', this);
  }

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
      return _iaic.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _iacc.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
