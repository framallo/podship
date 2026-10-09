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
import '../../integrations/models/provider.dart' as _i4ae2s7i;

/// One row per connect, disconnect, refused credential and credential read
/// (INT-7). Never holds a secret (INT-6).
abstract class IntegrationAudit
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  IntegrationAudit._({
    this.id,
    required this.workspaceId,
    required this.provider,
    required this.action,
    required this.actor,
    required this.ok,
    String? detail,
    DateTime? createdAt,
  }) : detail = detail ?? '',
       createdAt = createdAt ?? DateTime.now();

  factory IntegrationAudit({
    int? id,
    required int workspaceId,
    required _i4ae2s7i.IntegrationProvider provider,
    required String action,
    required String actor,
    required bool ok,
    String? detail,
    DateTime? createdAt,
  }) = _IntegrationAuditImpl;

  factory IntegrationAudit.fromJson(Map<String, dynamic> jsonSerialization) {
    return IntegrationAudit(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      provider: _i4ae2s7i.IntegrationProvider.fromJson(
        (jsonSerialization['provider'] as String),
      ),
      action: jsonSerialization['action'] as String,
      actor: jsonSerialization['actor'] as String,
      ok: _is.BoolJsonExtension.fromJson(jsonSerialization['ok']),
      detail: jsonSerialization['detail'] as String?,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  static final t = IntegrationAuditTable();

  static const db = IntegrationAuditRepository._();

  @override
  int? id;

  int workspaceId;

  _i4ae2s7i.IntegrationProvider provider;

  /// connect, connect_refused, disconnect, credential_read, aws_template,
  /// aws_callback, aws_stack_deleted, check_failed
  String action;

  /// The person's email or `token <name>` or `aws`.
  String actor;

  bool ok;

  String detail;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [IntegrationAudit]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  IntegrationAudit copyWith({
    int? id,
    int? workspaceId,
    _i4ae2s7i.IntegrationProvider? provider,
    String? action,
    String? actor,
    bool? ok,
    String? detail,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'IntegrationAudit',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      'provider': provider.toJson(),
      'action': action,
      'actor': actor,
      'ok': ok,
      'detail': detail,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static IntegrationAuditInclude include() {
    return IntegrationAuditInclude._();
  }

  static IntegrationAuditIncludeList includeList({
    _is.WhereExpressionBuilder<IntegrationAuditTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<IntegrationAuditTable>? orderBy,
    _is.OrderByListBuilder<IntegrationAuditTable>? orderByList,
    IntegrationAuditInclude? include,
  }) {
    return IntegrationAuditIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(IntegrationAudit.t),
      orderByList: orderByList?.call(IntegrationAudit.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _IntegrationAuditImpl extends IntegrationAudit {
  _IntegrationAuditImpl({
    int? id,
    required int workspaceId,
    required _i4ae2s7i.IntegrationProvider provider,
    required String action,
    required String actor,
    required bool ok,
    String? detail,
    DateTime? createdAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         provider: provider,
         action: action,
         actor: actor,
         ok: ok,
         detail: detail,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [IntegrationAudit]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  IntegrationAudit copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    _i4ae2s7i.IntegrationProvider? provider,
    String? action,
    String? actor,
    bool? ok,
    String? detail,
    DateTime? createdAt,
  }) {
    return IntegrationAudit(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      provider: provider ?? this.provider,
      action: action ?? this.action,
      actor: actor ?? this.actor,
      ok: ok ?? this.ok,
      detail: detail ?? this.detail,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class IntegrationAuditUpdateTable
    extends _is.UpdateTable<IntegrationAuditTable> {
  IntegrationAuditUpdateTable(super.table);

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<_i4ae2s7i.IntegrationProvider, _i4ae2s7i.IntegrationProvider>
  provider(_i4ae2s7i.IntegrationProvider value) => _is.ColumnValue(
    table.provider,
    value,
  );

  _is.ColumnValue<String, String> action(String value) => _is.ColumnValue(
    table.action,
    value,
  );

  _is.ColumnValue<String, String> actor(String value) => _is.ColumnValue(
    table.actor,
    value,
  );

  _is.ColumnValue<bool, bool> ok(bool value) => _is.ColumnValue(
    table.ok,
    value,
  );

  _is.ColumnValue<String, String> detail(String value) => _is.ColumnValue(
    table.detail,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class IntegrationAuditTable extends _is.Table<int?> {
  IntegrationAuditTable({super.tableRelation})
    : super(tableName: 'integration_audit') {
    updateTable = IntegrationAuditUpdateTable(this);
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    provider = _is.ColumnEnum(
      'provider',
      this,
      _is.EnumSerialization.byName,
    );
    action = _is.ColumnString(
      'action',
      this,
    );
    actor = _is.ColumnString(
      'actor',
      this,
    );
    ok = _is.ColumnBool(
      'ok',
      this,
    );
    detail = _is.ColumnString(
      'detail',
      this,
      hasDefault: true,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
      hasDefault: true,
    );
  }

  late final IntegrationAuditUpdateTable updateTable;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnEnum<_i4ae2s7i.IntegrationProvider> provider;

  /// connect, connect_refused, disconnect, credential_read, aws_template,
  /// aws_callback, aws_stack_deleted, check_failed
  late final _is.ColumnString action;

  /// The person's email or `token <name>` or `aws`.
  late final _is.ColumnString actor;

  late final _is.ColumnBool ok;

  late final _is.ColumnString detail;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    workspaceId,
    provider,
    action,
    actor,
    ok,
    detail,
    createdAt,
  ];
}

class IntegrationAuditInclude extends _is.IncludeObject {
  IntegrationAuditInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => IntegrationAudit.t;
}

class IntegrationAuditIncludeList extends _is.IncludeList {
  IntegrationAuditIncludeList._({
    _is.WhereExpressionBuilder<IntegrationAuditTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(IntegrationAudit.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => IntegrationAudit.t;
}

class IntegrationAuditRepository {
  const IntegrationAuditRepository._();

  /// Returns a list of [IntegrationAudit]s matching the given query parameters.
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
  Future<List<IntegrationAudit>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<IntegrationAuditTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<IntegrationAuditTable>? orderBy,
    _is.OrderByListBuilder<IntegrationAuditTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<IntegrationAudit>(
      where: where?.call(IntegrationAudit.t),
      orderBy: orderBy?.call(IntegrationAudit.t),
      orderByList: orderByList?.call(IntegrationAudit.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [IntegrationAudit] matching the given query parameters.
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
  Future<IntegrationAudit?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<IntegrationAuditTable>? where,
    int? offset,
    _is.OrderByBuilder<IntegrationAuditTable>? orderBy,
    _is.OrderByListBuilder<IntegrationAuditTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<IntegrationAudit>(
      where: where?.call(IntegrationAudit.t),
      orderBy: orderBy?.call(IntegrationAudit.t),
      orderByList: orderByList?.call(IntegrationAudit.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [IntegrationAudit] by its [id] or null if no such row exists.
  Future<IntegrationAudit?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<IntegrationAudit>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [IntegrationAudit]s in the list and returns the inserted rows.
  ///
  /// The returned [IntegrationAudit]s will have their `id` fields set.
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
  Future<List<IntegrationAudit>> insert(
    _is.DatabaseSession session,
    List<IntegrationAudit> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<IntegrationAudit>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [IntegrationAudit] and returns the inserted row.
  ///
  /// The returned [IntegrationAudit] will have its `id` field set.
  Future<IntegrationAudit> insertRow(
    _is.DatabaseSession session,
    IntegrationAudit row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<IntegrationAudit>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [IntegrationAudit]s in the list and returns the resulting rows.
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
  /// The returned [IntegrationAudit]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<IntegrationAudit>> upsert(
    _is.DatabaseSession session,
    List<IntegrationAudit> rows, {
    required _is.ColumnSelections<IntegrationAuditTable> conflictColumns,
    _is.ColumnSelections<IntegrationAuditTable>? updateColumns,
    _is.WhereExpressionBuilder<IntegrationAuditTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<IntegrationAudit>(
      rows,
      conflictColumns: conflictColumns(IntegrationAudit.t),
      updateColumns: updateColumns?.call(IntegrationAudit.t),
      updateWhere: updateWhere?.call(IntegrationAudit.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [IntegrationAudit] and returns the resulting row.
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
  /// The returned [IntegrationAudit] will have its `id` field set.
  Future<IntegrationAudit?> upsertRow(
    _is.DatabaseSession session,
    IntegrationAudit row, {
    required _is.ColumnSelections<IntegrationAuditTable> conflictColumns,
    _is.ColumnSelections<IntegrationAuditTable>? updateColumns,
    _is.WhereExpressionBuilder<IntegrationAuditTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<IntegrationAudit>(
      row,
      conflictColumns: conflictColumns(IntegrationAudit.t),
      updateColumns: updateColumns?.call(IntegrationAudit.t),
      updateWhere: updateWhere?.call(IntegrationAudit.t),
      transaction: transaction,
    );
  }

  /// Updates all [IntegrationAudit]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<IntegrationAudit>> update(
    _is.DatabaseSession session,
    List<IntegrationAudit> rows, {
    _is.ColumnSelections<IntegrationAuditTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<IntegrationAudit>(
      rows,
      columns: columns?.call(IntegrationAudit.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [IntegrationAudit]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<IntegrationAudit> updateRow(
    _is.DatabaseSession session,
    IntegrationAudit row, {
    _is.ColumnSelections<IntegrationAuditTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<IntegrationAudit>(
      row,
      columns: columns?.call(IntegrationAudit.t),
      transaction: transaction,
    );
  }

  /// Updates a single [IntegrationAudit] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<IntegrationAudit?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<IntegrationAuditUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<IntegrationAudit>(
      id,
      columnValues: columnValues(IntegrationAudit.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [IntegrationAudit]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<IntegrationAudit>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<IntegrationAuditUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<IntegrationAuditTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<IntegrationAuditTable>? orderBy,
    _is.OrderByListBuilder<IntegrationAuditTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<IntegrationAudit>(
      columnValues: columnValues(IntegrationAudit.t.updateTable),
      where: where(IntegrationAudit.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(IntegrationAudit.t),
      orderByList: orderByList?.call(IntegrationAudit.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [IntegrationAudit]s in the list and returns the deleted rows.
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
  Future<List<IntegrationAudit>> delete(
    _is.DatabaseSession session,
    List<IntegrationAudit> rows, {
    _is.OrderByBuilder<IntegrationAuditTable>? orderBy,
    _is.OrderByListBuilder<IntegrationAuditTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<IntegrationAudit>(
      rows,
      orderBy: orderBy?.call(IntegrationAudit.t),
      orderByList: orderByList?.call(IntegrationAudit.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [IntegrationAudit].
  Future<IntegrationAudit> deleteRow(
    _is.DatabaseSession session,
    IntegrationAudit row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<IntegrationAudit>(
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
  Future<List<IntegrationAudit>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<IntegrationAuditTable> where,
    _is.OrderByBuilder<IntegrationAuditTable>? orderBy,
    _is.OrderByListBuilder<IntegrationAuditTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<IntegrationAudit>(
      where: where(IntegrationAudit.t),
      orderBy: orderBy?.call(IntegrationAudit.t),
      orderByList: orderByList?.call(IntegrationAudit.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<IntegrationAuditTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<IntegrationAudit>(
      where: where?.call(IntegrationAudit.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [IntegrationAudit] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<IntegrationAuditTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<IntegrationAudit>(
      where: where(IntegrationAudit.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
