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
import '../../integrations/models/provider.dart' as _i4ae2s7i;

/// What the browser sees of an integration: never the credential (INT-5).
abstract class IntegrationView
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  IntegrationView._({
    required this.provider,
    required this.status,
    this.hint,
    this.account,
    this.zones,
    this.role,
    this.sesRegion,
    this.sesProduction,
    this.connectedBy,
    this.connectedAt,
    this.pendingSince,
    this.lastCheckAt,
    this.lastCheckOk,
    this.lastError,
  });

  factory IntegrationView({
    required _i4ae2s7i.IntegrationProvider provider,
    required String status,
    String? hint,
    String? account,
    int? zones,
    String? role,
    String? sesRegion,
    bool? sesProduction,
    String? connectedBy,
    DateTime? connectedAt,
    DateTime? pendingSince,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastError,
  }) = _IntegrationViewImpl;

  factory IntegrationView.fromJson(Map<String, dynamic> jsonSerialization) {
    return IntegrationView(
      provider: _i4ae2s7i.IntegrationProvider.fromJson(
        (jsonSerialization['provider'] as String),
      ),
      status: jsonSerialization['status'] as String,
      hint: jsonSerialization['hint'] as String?,
      account: jsonSerialization['account'] as String?,
      zones: jsonSerialization['zones'] as int?,
      role: jsonSerialization['role'] as String?,
      sesRegion: jsonSerialization['sesRegion'] as String?,
      sesProduction: jsonSerialization['sesProduction'] == null
          ? null
          : _isc.BoolJsonExtension.fromJson(jsonSerialization['sesProduction']),
      connectedBy: jsonSerialization['connectedBy'] as String?,
      connectedAt: jsonSerialization['connectedAt'] == null
          ? null
          : _isc.DateTimeJsonExtension.fromJson(
              jsonSerialization['connectedAt'],
            ),
      pendingSince: jsonSerialization['pendingSince'] == null
          ? null
          : _isc.DateTimeJsonExtension.fromJson(
              jsonSerialization['pendingSince'],
            ),
      lastCheckAt: jsonSerialization['lastCheckAt'] == null
          ? null
          : _isc.DateTimeJsonExtension.fromJson(
              jsonSerialization['lastCheckAt'],
            ),
      lastCheckOk: jsonSerialization['lastCheckOk'] == null
          ? null
          : _isc.BoolJsonExtension.fromJson(jsonSerialization['lastCheckOk']),
      lastError: jsonSerialization['lastError'] as String?,
    );
  }

  _i4ae2s7i.IntegrationProvider provider;

  /// off, pending, connected
  String status;

  String? hint;

  /// Cloudflare: account name. AWS: account id.
  String? account;

  /// Cloudflare: number of zones.
  int? zones;

  /// AWS: role name, SES region and mode.
  String? role;

  String? sesRegion;

  bool? sesProduction;

  String? connectedBy;

  DateTime? connectedAt;

  DateTime? pendingSince;

  DateTime? lastCheckAt;

  bool? lastCheckOk;

  String? lastError;

  /// Returns a shallow copy of this [IntegrationView]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  IntegrationView copyWith({
    _i4ae2s7i.IntegrationProvider? provider,
    String? status,
    String? hint,
    String? account,
    int? zones,
    String? role,
    String? sesRegion,
    bool? sesProduction,
    String? connectedBy,
    DateTime? connectedAt,
    DateTime? pendingSince,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastError,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'IntegrationView',
      'provider': provider.toJson(),
      'status': status,
      if (hint != null) 'hint': hint,
      if (account != null) 'account': account,
      if (zones != null) 'zones': zones,
      if (role != null) 'role': role,
      if (sesRegion != null) 'sesRegion': sesRegion,
      if (sesProduction != null) 'sesProduction': sesProduction,
      if (connectedBy != null) 'connectedBy': connectedBy,
      if (connectedAt != null) 'connectedAt': connectedAt?.toJson(),
      if (pendingSince != null) 'pendingSince': pendingSince?.toJson(),
      if (lastCheckAt != null) 'lastCheckAt': lastCheckAt?.toJson(),
      if (lastCheckOk != null) 'lastCheckOk': lastCheckOk,
      if (lastError != null) 'lastError': lastError,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'IntegrationView',
      'provider': provider.toJson(),
      'status': status,
      if (hint != null) 'hint': hint,
      if (account != null) 'account': account,
      if (zones != null) 'zones': zones,
      if (role != null) 'role': role,
      if (sesRegion != null) 'sesRegion': sesRegion,
      if (sesProduction != null) 'sesProduction': sesProduction,
      if (connectedBy != null) 'connectedBy': connectedBy,
      if (connectedAt != null) 'connectedAt': connectedAt?.toJson(),
      if (pendingSince != null) 'pendingSince': pendingSince?.toJson(),
      if (lastCheckAt != null) 'lastCheckAt': lastCheckAt?.toJson(),
      if (lastCheckOk != null) 'lastCheckOk': lastCheckOk,
      if (lastError != null) 'lastError': lastError,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _IntegrationViewImpl extends IntegrationView {
  _IntegrationViewImpl({
    required _i4ae2s7i.IntegrationProvider provider,
    required String status,
    String? hint,
    String? account,
    int? zones,
    String? role,
    String? sesRegion,
    bool? sesProduction,
    String? connectedBy,
    DateTime? connectedAt,
    DateTime? pendingSince,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastError,
  }) : super._(
         provider: provider,
         status: status,
         hint: hint,
         account: account,
         zones: zones,
         role: role,
         sesRegion: sesRegion,
         sesProduction: sesProduction,
         connectedBy: connectedBy,
         connectedAt: connectedAt,
         pendingSince: pendingSince,
         lastCheckAt: lastCheckAt,
         lastCheckOk: lastCheckOk,
         lastError: lastError,
       );

  /// Returns a shallow copy of this [IntegrationView]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  IntegrationView copyWith({
    _i4ae2s7i.IntegrationProvider? provider,
    String? status,
    Object? hint = _Undefined,
    Object? account = _Undefined,
    Object? zones = _Undefined,
    Object? role = _Undefined,
    Object? sesRegion = _Undefined,
    Object? sesProduction = _Undefined,
    Object? connectedBy = _Undefined,
    Object? connectedAt = _Undefined,
    Object? pendingSince = _Undefined,
    Object? lastCheckAt = _Undefined,
    Object? lastCheckOk = _Undefined,
    Object? lastError = _Undefined,
  }) {
    return IntegrationView(
      provider: provider ?? this.provider,
      status: status ?? this.status,
      hint: hint is String? ? hint : this.hint,
      account: account is String? ? account : this.account,
      zones: zones is int? ? zones : this.zones,
      role: role is String? ? role : this.role,
      sesRegion: sesRegion is String? ? sesRegion : this.sesRegion,
      sesProduction: sesProduction is bool?
          ? sesProduction
          : this.sesProduction,
      connectedBy: connectedBy is String? ? connectedBy : this.connectedBy,
      connectedAt: connectedAt is DateTime? ? connectedAt : this.connectedAt,
      pendingSince: pendingSince is DateTime?
          ? pendingSince
          : this.pendingSince,
      lastCheckAt: lastCheckAt is DateTime? ? lastCheckAt : this.lastCheckAt,
      lastCheckOk: lastCheckOk is bool? ? lastCheckOk : this.lastCheckOk,
      lastError: lastError is String? ? lastError : this.lastError,
    );
  }
}
