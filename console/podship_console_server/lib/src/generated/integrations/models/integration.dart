/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: dead_code, unnecessary_null_comparison

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:podship_console_server/src/generated/protocol.dart'
    as _itytg29z;
import 'package:serverpod/serverpod.dart' as _is;
import '../../integrations/models/provider.dart' as _i4ae2s7i;
import '../../workspace/models/workspace.dart' as _ikenbmzt;

/// A workspace's connection to a provider (INT-1, INT-2). The credential is
/// encrypted with AES-256-GCM (INT-4); it never leaves the server for the
/// browser (INT-5).
abstract class Integration
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  Integration._({
    this.id,
    required this.workspaceId,
    this.workspace,
    required this.provider,
    required this.status,
    this.secret,
    this.hint,
    String? details,
    this.connectedBy,
    this.connectedAt,
    this.lastCheckAt,
    this.lastCheckOk,
    this.lastError,
    DateTime? updatedAt,
  }) : details = details ?? '{}',
       updatedAt = updatedAt ?? DateTime.now();

  factory Integration({
    int? id,
    required int workspaceId,
    _ikenbmzt.Workspace? workspace,
    required _i4ae2s7i.IntegrationProvider provider,
    required String status,
    String? secret,
    String? hint,
    String? details,
    String? connectedBy,
    DateTime? connectedAt,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastError,
    DateTime? updatedAt,
  }) = _IntegrationImpl;

  factory Integration.fromJson(Map<String, dynamic> jsonSerialization) {
    return Integration(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      workspace: jsonSerialization['workspace'] == null
          ? null
          : _itytg29z.Protocol().deserialize<_ikenbmzt.Workspace>(
              jsonSerialization['workspace'],
            ),
      provider: _i4ae2s7i.IntegrationProvider.fromJson(
        (jsonSerialization['provider'] as String),
      ),
      status: jsonSerialization['status'] as String,
      secret: jsonSerialization['secret'] as String?,
      hint: jsonSerialization['hint'] as String?,
      details: jsonSerialization['details'] as String?,
      connectedBy: jsonSerialization['connectedBy'] as String?,
      connectedAt: jsonSerialization['connectedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['connectedAt'],
            ),
      lastCheckAt: jsonSerialization['lastCheckAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['lastCheckAt'],
            ),
      lastCheckOk: jsonSerialization['lastCheckOk'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['lastCheckOk']),
      lastError: jsonSerialization['lastError'] as String?,
      updatedAt: jsonSerialization['updatedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['updatedAt']),
    );
  }

  static final t = IntegrationTable();

  static const db = IntegrationRepository._();

  @override
  int? id;

  int workspaceId;

  _ikenbmzt.Workspace? workspace;

  _i4ae2s7i.IntegrationProvider provider;

  /// `pending` (AWS: waiting for the stack) or `connected`.
  String status;

  /// Encrypted credential (Cloudflare: the token; AWS: the role ARN). Null
  /// while pending.
  String? secret;

  /// Last 4 characters of the credential, for the UI.
  String? hint;

  /// Facts without secrets, as JSON: account name and id, zones, role,
  /// SES region and mode, stack id.
  String details;

  String? connectedBy;

  DateTime? connectedAt;

  DateTime? lastCheckAt;

  bool? lastCheckOk;

  String? lastError;

  DateTime updatedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [Integration]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  Integration copyWith({
    int? id,
    int? workspaceId,
    _ikenbmzt.Workspace? workspace,
    _i4ae2s7i.IntegrationProvider? provider,
    String? status,
    String? secret,
    String? hint,
    String? details,
    String? connectedBy,
    DateTime? connectedAt,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastError,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Integration',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      if (workspace != null) 'workspace': workspace?.toJson(),
      'provider': provider.toJson(),
      'status': status,
      if (secret != null) 'secret': secret,
      if (hint != null) 'hint': hint,
      'details': details,
      if (connectedBy != null) 'connectedBy': connectedBy,
      if (connectedAt != null) 'connectedAt': connectedAt?.toJson(),
      if (lastCheckAt != null) 'lastCheckAt': lastCheckAt?.toJson(),
      if (lastCheckOk != null) 'lastCheckOk': lastCheckOk,
      if (lastError != null) 'lastError': lastError,
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static IntegrationInclude include({_ikenbmzt.WorkspaceInclude? workspace}) {
    return IntegrationInclude._(workspace: workspace);
  }

  static IntegrationIncludeList includeList({
    _is.WhereExpressionBuilder<IntegrationTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<IntegrationTable>? orderBy,
    _is.OrderByListBuilder<IntegrationTable>? orderByList,
    IntegrationInclude? include,
  }) {
    return IntegrationIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Integration.t),
      orderByList: orderByList?.call(Integration.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _IntegrationImpl extends Integration {
  _IntegrationImpl({
    int? id,
    required int workspaceId,
    _ikenbmzt.Workspace? workspace,
    required _i4ae2s7i.IntegrationProvider provider,
    required String status,
    String? secret,
    String? hint,
    String? details,
    String? connectedBy,
    DateTime? connectedAt,
    DateTime? lastCheckAt,
    bool? lastCheckOk,
    String? lastError,
    DateTime? updatedAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         workspace: workspace,
         provider: provider,
         status: status,
         secret: secret,
         hint: hint,
         details: details,
         connectedBy: connectedBy,
         connectedAt: connectedAt,
         lastCheckAt: lastCheckAt,
         lastCheckOk: lastCheckOk,
         lastError: lastError,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [Integration]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  Integration copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    Object? workspace = _Undefined,
    _i4ae2s7i.IntegrationProvider? provider,
    String? status,
    Object? secret = _Undefined,
    Object? hint = _Undefined,
    String? details,
    Object? connectedBy = _Undefined,
    Object? connectedAt = _Undefined,
    Object? lastCheckAt = _Undefined,
    Object? lastCheckOk = _Undefined,
    Object? lastError = _Undefined,
    DateTime? updatedAt,
  }) {
    return Integration(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      workspace: workspace is _ikenbmzt.Workspace?
          ? workspace
          : this.workspace?.copyWith(),
      provider: provider ?? this.provider,
      status: status ?? this.status,
      secret: secret is String? ? secret : this.secret,
      hint: hint is String? ? hint : this.hint,
      details: details ?? this.details,
      connectedBy: connectedBy is String? ? connectedBy : this.connectedBy,
      connectedAt: connectedAt is DateTime? ? connectedAt : this.connectedAt,
      lastCheckAt: lastCheckAt is DateTime? ? lastCheckAt : this.lastCheckAt,
      lastCheckOk: lastCheckOk is bool? ? lastCheckOk : this.lastCheckOk,
      lastError: lastError is String? ? lastError : this.lastError,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class IntegrationUpdateTable extends _is.UpdateTable<IntegrationTable> {
  IntegrationUpdateTable(super.table);

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<_i4ae2s7i.IntegrationProvider, _i4ae2s7i.IntegrationProvider>
  provider(_i4ae2s7i.IntegrationProvider value) => _is.ColumnValue(
    table.provider,
    value,
  );

  _is.ColumnValue<String, String> status(String value) => _is.ColumnValue(
    table.status,
    value,
  );

  _is.ColumnValue<String, String> secret(String? value) => _is.ColumnValue(
    table.secret,
    value,
  );

  _is.ColumnValue<String, String> hint(String? value) => _is.ColumnValue(
    table.hint,
    value,
  );

  _is.ColumnValue<String, String> details(String value) => _is.ColumnValue(
    table.details,
    value,
  );

  _is.ColumnValue<String, String> connectedBy(String? value) => _is.ColumnValue(
    table.connectedBy,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> connectedAt(DateTime? value) =>
      _is.ColumnValue(
        table.connectedAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> lastCheckAt(DateTime? value) =>
      _is.ColumnValue(
        table.lastCheckAt,
        value,
      );

  _is.ColumnValue<bool, bool> lastCheckOk(bool? value) => _is.ColumnValue(
    table.lastCheckOk,
    value,
  );

  _is.ColumnValue<String, String> lastError(String? value) => _is.ColumnValue(
    table.lastError,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> updatedAt(DateTime value) =>
      _is.ColumnValue(
        table.updatedAt,
        value,
      );
}

class IntegrationTable extends _is.Table<int?> {
  IntegrationTable({super.tableRelation}) : super(tableName: 'integration') {
    updateTable = IntegrationUpdateTable(this);
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    provider = _is.ColumnEnum(
      'provider',
      this,
      _is.EnumSerialization.byName,
    );
    status = _is.ColumnString(
      'status',
      this,
    );
    secret = _is.ColumnString(
      'secret',
      this,
    );
    hint = _is.ColumnString(
      'hint',
      this,
    );
    details = _is.ColumnString(
      'details',
      this,
      hasDefault: true,
    );
    connectedBy = _is.ColumnString(
      'connectedBy',
      this,
    );
    connectedAt = _is.ColumnDateTime(
      'connectedAt',
      this,
    );
    lastCheckAt = _is.ColumnDateTime(
      'lastCheckAt',
      this,
    );
    lastCheckOk = _is.ColumnBool(
      'lastCheckOk',
      this,
    );
    lastError = _is.ColumnString(
      'lastError',
      this,
    );
    updatedAt = _is.ColumnDateTime(
      'updatedAt',
      this,
      hasDefault: true,
    );
  }

  late final IntegrationUpdateTable updateTable;

  late final _is.ColumnInt workspaceId;

  _ikenbmzt.WorkspaceTable? _workspace;

  late final _is.ColumnEnum<_i4ae2s7i.IntegrationProvider> provider;

  /// `pending` (AWS: waiting for the stack) or `connected`.
  late final _is.ColumnString status;

  /// Encrypted credential (Cloudflare: the token; AWS: the role ARN). Null
  /// while pending.
  late final _is.ColumnString secret;

  /// Last 4 characters of the credential, for the UI.
  late final _is.ColumnString hint;

  /// Facts without secrets, as JSON: account name and id, zones, role,
  /// SES region and mode, stack id.
  late final _is.ColumnString details;

  late final _is.ColumnString connectedBy;

  late final _is.ColumnDateTime connectedAt;

  late final _is.ColumnDateTime lastCheckAt;

  late final _is.ColumnBool lastCheckOk;

  late final _is.ColumnString lastError;

  late final _is.ColumnDateTime updatedAt;

  _ikenbmzt.WorkspaceTable get workspace {
    if (_workspace != null) return _workspace!;
    _workspace = _is.createRelationTable(
      relationFieldName: 'workspace',
      field: Integration.t.workspaceId,
      foreignField: _ikenbmzt.Workspace.t.id,
      tableRelation: tableRelation,
      createTable: (foreignTableRelation) =>
          _ikenbmzt.WorkspaceTable(tableRelation: foreignTableRelation),
    );
    return _workspace!;
  }

  @override
  List<_is.Column> get columns => [
    id,
    workspaceId,
    provider,
    status,
    secret,
    hint,
    details,
    connectedBy,
    connectedAt,
    lastCheckAt,
    lastCheckOk,
    lastError,
    updatedAt,
  ];

  @override
  _is.Table? getRelationTable(String relationField) {
    if (relationField == 'workspace') {
      return workspace;
    }
    return null;
  }
}

class IntegrationInclude extends _is.IncludeObject {
  IntegrationInclude._({_ikenbmzt.WorkspaceInclude? workspace}) {
    _workspace = workspace;
  }

  _ikenbmzt.WorkspaceInclude? _workspace;

  @override
  Map<String, _is.Include?> get includes => {'workspace': _workspace};

  @override
  _is.Table<int?> get table => Integration.t;
}

class IntegrationIncludeList extends _is.IncludeList {
  IntegrationIncludeList._({
    _is.WhereExpressionBuilder<IntegrationTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Integration.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => Integration.t;
}

class IntegrationRepository {
  const IntegrationRepository._();

  final attachRow = const IntegrationAttachRowRepository._();

  /// Returns a list of [Integration]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<Integration>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<IntegrationTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<IntegrationTable>? orderBy,
    _is.OrderByListBuilder<IntegrationTable>? orderByList,
    _is.Transaction? transaction,
    IntegrationInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Integration>(
      where: where?.call(Integration.t),
      orderBy: orderBy?.call(Integration.t),
      orderByList: orderByList?.call(Integration.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Integration] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<Integration?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<IntegrationTable>? where,
    int? offset,
    _is.OrderByBuilder<IntegrationTable>? orderBy,
    _is.OrderByListBuilder<IntegrationTable>? orderByList,
    _is.Transaction? transaction,
    IntegrationInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Integration>(
      where: where?.call(Integration.t),
      orderBy: orderBy?.call(Integration.t),
      orderByList: orderByList?.call(Integration.t),
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Integration] by its [id] or null if no such row exists.
  Future<Integration?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    IntegrationInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Integration>(
      id,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Integration]s in the list and returns the inserted rows.
  ///
  /// The returned [Integration]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  ///
  /// If [noReturn] is set to `true`, the inserted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Integration>> insert(
    _is.DatabaseSession session,
    List<Integration> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<Integration>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [Integration] and returns the inserted row.
  ///
  /// The returned [Integration] will have its `id` field set.
  Future<Integration> insertRow(
    _is.DatabaseSession session,
    Integration row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<Integration>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [Integration]s in the list and returns the resulting rows.
  ///
  /// If a row conflicts on the given [conflictColumns], the existing row is
  /// updated with the new values. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies to rows matching the
  /// given expression. Conflicting rows that don't match are skipped and not
  /// returned, so the resulting list may be shorter than [rows].
  ///
  /// The returned [Integration]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Integration>> upsert(
    _is.DatabaseSession session,
    List<Integration> rows, {
    required _is.ColumnSelections<IntegrationTable> conflictColumns,
    _is.ColumnSelections<IntegrationTable>? updateColumns,
    _is.WhereExpressionBuilder<IntegrationTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<Integration>(
      rows,
      conflictColumns: conflictColumns(Integration.t),
      updateColumns: updateColumns?.call(Integration.t),
      updateWhere: updateWhere?.call(Integration.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [Integration] and returns the resulting row.
  ///
  /// If the row conflicts on the given [conflictColumns], the existing row is
  /// updated. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies when the existing
  /// row matches the expression. Returns `null` if no row was affected — for
  /// example when [updateWhere] does not match the conflicting row.
  ///
  /// The returned [Integration] will have its `id` field set.
  Future<Integration?> upsertRow(
    _is.DatabaseSession session,
    Integration row, {
    required _is.ColumnSelections<IntegrationTable> conflictColumns,
    _is.ColumnSelections<IntegrationTable>? updateColumns,
    _is.WhereExpressionBuilder<IntegrationTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<Integration>(
      row,
      conflictColumns: conflictColumns(Integration.t),
      updateColumns: updateColumns?.call(Integration.t),
      updateWhere: updateWhere?.call(Integration.t),
      transaction: transaction,
    );
  }

  /// Updates all [Integration]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Integration>> update(
    _is.DatabaseSession session,
    List<Integration> rows, {
    _is.ColumnSelections<IntegrationTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<Integration>(
      rows,
      columns: columns?.call(Integration.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [Integration]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Integration> updateRow(
    _is.DatabaseSession session,
    Integration row, {
    _is.ColumnSelections<IntegrationTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<Integration>(
      row,
      columns: columns?.call(Integration.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Integration] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Integration?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<IntegrationUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<Integration>(
      id,
      columnValues: columnValues(Integration.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Integration]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Integration>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<IntegrationUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<IntegrationTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<IntegrationTable>? orderBy,
    _is.OrderByListBuilder<IntegrationTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<Integration>(
      columnValues: columnValues(Integration.t.updateTable),
      where: where(Integration.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Integration.t),
      orderByList: orderByList?.call(Integration.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [Integration]s in the list and returns the deleted rows.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Integration>> delete(
    _is.DatabaseSession session,
    List<Integration> rows, {
    _is.OrderByBuilder<IntegrationTable>? orderBy,
    _is.OrderByListBuilder<IntegrationTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<Integration>(
      rows,
      orderBy: orderBy?.call(Integration.t),
      orderByList: orderByList?.call(Integration.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [Integration].
  Future<Integration> deleteRow(
    _is.DatabaseSession session,
    Integration row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Integration>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Integration>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<IntegrationTable> where,
    _is.OrderByBuilder<IntegrationTable>? orderBy,
    _is.OrderByListBuilder<IntegrationTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<Integration>(
      where: where(Integration.t),
      orderBy: orderBy?.call(Integration.t),
      orderByList: orderByList?.call(Integration.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<IntegrationTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<Integration>(
      where: where?.call(Integration.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Integration] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<IntegrationTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Integration>(
      where: where(Integration.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}

class IntegrationAttachRowRepository {
  const IntegrationAttachRowRepository._();

  /// Creates a relation between the given [Integration] and [Workspace]
  /// by setting the [Integration]'s foreign key `workspaceId` to refer to the [Workspace].
  Future<void> workspace(
    _is.DatabaseSession session,
    Integration integration,
    _ikenbmzt.Workspace workspace, {
    _is.Transaction? transaction,
  }) async {
    if (integration.id == null) {
      throw ArgumentError.notNull('integration.id');
    }
    if (workspace.id == null) {
      throw ArgumentError.notNull('workspace.id');
    }

    var $integration = integration.copyWith(workspaceId: workspace.id);
    await session.db.updateRow<Integration>(
      $integration,
      columns: [Integration.t.workspaceId],
      transaction: transaction,
    );
  }
}
