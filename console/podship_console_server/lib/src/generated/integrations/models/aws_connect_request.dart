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

/// The one-time code inside an AWS template (INT-12).
abstract class AwsConnectRequest
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AwsConnectRequest._({
    this.id,
    required this.workspaceId,
    required this.codeHash,
    required this.createdBy,
    DateTime? createdAt,
    required this.expiresAt,
    this.usedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AwsConnectRequest({
    int? id,
    required int workspaceId,
    required String codeHash,
    required String createdBy,
    DateTime? createdAt,
    required DateTime expiresAt,
    DateTime? usedAt,
  }) = _AwsConnectRequestImpl;

  factory AwsConnectRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return AwsConnectRequest(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      codeHash: jsonSerialization['codeHash'] as String,
      createdBy: jsonSerialization['createdBy'] as String,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
      expiresAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      usedAt: jsonSerialization['usedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['usedAt']),
    );
  }

  static final t = AwsConnectRequestTable();

  static const db = AwsConnectRequestRepository._();

  @override
  int? id;

  int workspaceId;

  /// SHA-256 of the code.
  String codeHash;

  String createdBy;

  DateTime createdAt;

  DateTime expiresAt;

  DateTime? usedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AwsConnectRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AwsConnectRequest copyWith({
    int? id,
    int? workspaceId,
    String? codeHash,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? usedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AwsConnectRequest',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      'codeHash': codeHash,
      'createdBy': createdBy,
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (usedAt != null) 'usedAt': usedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AwsConnectRequestInclude include() {
    return AwsConnectRequestInclude._();
  }

  static AwsConnectRequestIncludeList includeList({
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AwsConnectRequestTable>? orderBy,
    _is.OrderByListBuilder<AwsConnectRequestTable>? orderByList,
    AwsConnectRequestInclude? include,
  }) {
    return AwsConnectRequestIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AwsConnectRequest.t),
      orderByList: orderByList?.call(AwsConnectRequest.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AwsConnectRequestImpl extends AwsConnectRequest {
  _AwsConnectRequestImpl({
    int? id,
    required int workspaceId,
    required String codeHash,
    required String createdBy,
    DateTime? createdAt,
    required DateTime expiresAt,
    DateTime? usedAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         codeHash: codeHash,
         createdBy: createdBy,
         createdAt: createdAt,
         expiresAt: expiresAt,
         usedAt: usedAt,
       );

  /// Returns a shallow copy of this [AwsConnectRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AwsConnectRequest copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    String? codeHash,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
    Object? usedAt = _Undefined,
  }) {
    return AwsConnectRequest(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      codeHash: codeHash ?? this.codeHash,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      usedAt: usedAt is DateTime? ? usedAt : this.usedAt,
    );
  }
}

class AwsConnectRequestUpdateTable
    extends _is.UpdateTable<AwsConnectRequestTable> {
  AwsConnectRequestUpdateTable(super.table);

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> codeHash(String value) => _is.ColumnValue(
    table.codeHash,
    value,
  );

  _is.ColumnValue<String, String> createdBy(String value) => _is.ColumnValue(
    table.createdBy,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> expiresAt(DateTime value) =>
      _is.ColumnValue(
        table.expiresAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> usedAt(DateTime? value) =>
      _is.ColumnValue(
        table.usedAt,
        value,
      );
}

class AwsConnectRequestTable extends _is.Table<int?> {
  AwsConnectRequestTable({super.tableRelation})
    : super(tableName: 'aws_connect_request') {
    updateTable = AwsConnectRequestUpdateTable(this);
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    codeHash = _is.ColumnString(
      'codeHash',
      this,
    );
    createdBy = _is.ColumnString(
      'createdBy',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
      hasDefault: true,
    );
    expiresAt = _is.ColumnDateTime(
      'expiresAt',
      this,
    );
    usedAt = _is.ColumnDateTime(
      'usedAt',
      this,
    );
  }

  late final AwsConnectRequestUpdateTable updateTable;

  late final _is.ColumnInt workspaceId;

  /// SHA-256 of the code.
  late final _is.ColumnString codeHash;

  late final _is.ColumnString createdBy;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime expiresAt;

  late final _is.ColumnDateTime usedAt;

  @override
  List<_is.Column> get columns => [
    id,
    workspaceId,
    codeHash,
    createdBy,
    createdAt,
    expiresAt,
    usedAt,
  ];
}

class AwsConnectRequestInclude extends _is.IncludeObject {
  AwsConnectRequestInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AwsConnectRequest.t;
}

class AwsConnectRequestIncludeList extends _is.IncludeList {
  AwsConnectRequestIncludeList._({
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AwsConnectRequest.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AwsConnectRequest.t;
}

class AwsConnectRequestRepository {
  const AwsConnectRequestRepository._();

  /// Returns a list of [AwsConnectRequest]s matching the given query parameters.
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
  Future<List<AwsConnectRequest>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AwsConnectRequestTable>? orderBy,
    _is.OrderByListBuilder<AwsConnectRequestTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AwsConnectRequest>(
      where: where?.call(AwsConnectRequest.t),
      orderBy: orderBy?.call(AwsConnectRequest.t),
      orderByList: orderByList?.call(AwsConnectRequest.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AwsConnectRequest] matching the given query parameters.
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
  Future<AwsConnectRequest?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? where,
    int? offset,
    _is.OrderByBuilder<AwsConnectRequestTable>? orderBy,
    _is.OrderByListBuilder<AwsConnectRequestTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AwsConnectRequest>(
      where: where?.call(AwsConnectRequest.t),
      orderBy: orderBy?.call(AwsConnectRequest.t),
      orderByList: orderByList?.call(AwsConnectRequest.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AwsConnectRequest] by its [id] or null if no such row exists.
  Future<AwsConnectRequest?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AwsConnectRequest>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AwsConnectRequest]s in the list and returns the inserted rows.
  ///
  /// The returned [AwsConnectRequest]s will have their `id` fields set.
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
  Future<List<AwsConnectRequest>> insert(
    _is.DatabaseSession session,
    List<AwsConnectRequest> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AwsConnectRequest>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AwsConnectRequest] and returns the inserted row.
  ///
  /// The returned [AwsConnectRequest] will have its `id` field set.
  Future<AwsConnectRequest> insertRow(
    _is.DatabaseSession session,
    AwsConnectRequest row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AwsConnectRequest>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AwsConnectRequest]s in the list and returns the resulting rows.
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
  /// The returned [AwsConnectRequest]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AwsConnectRequest>> upsert(
    _is.DatabaseSession session,
    List<AwsConnectRequest> rows, {
    required _is.ColumnSelections<AwsConnectRequestTable> conflictColumns,
    _is.ColumnSelections<AwsConnectRequestTable>? updateColumns,
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AwsConnectRequest>(
      rows,
      conflictColumns: conflictColumns(AwsConnectRequest.t),
      updateColumns: updateColumns?.call(AwsConnectRequest.t),
      updateWhere: updateWhere?.call(AwsConnectRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AwsConnectRequest] and returns the resulting row.
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
  /// The returned [AwsConnectRequest] will have its `id` field set.
  Future<AwsConnectRequest?> upsertRow(
    _is.DatabaseSession session,
    AwsConnectRequest row, {
    required _is.ColumnSelections<AwsConnectRequestTable> conflictColumns,
    _is.ColumnSelections<AwsConnectRequestTable>? updateColumns,
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AwsConnectRequest>(
      row,
      conflictColumns: conflictColumns(AwsConnectRequest.t),
      updateColumns: updateColumns?.call(AwsConnectRequest.t),
      updateWhere: updateWhere?.call(AwsConnectRequest.t),
      transaction: transaction,
    );
  }

  /// Updates all [AwsConnectRequest]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AwsConnectRequest>> update(
    _is.DatabaseSession session,
    List<AwsConnectRequest> rows, {
    _is.ColumnSelections<AwsConnectRequestTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AwsConnectRequest>(
      rows,
      columns: columns?.call(AwsConnectRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AwsConnectRequest]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AwsConnectRequest> updateRow(
    _is.DatabaseSession session,
    AwsConnectRequest row, {
    _is.ColumnSelections<AwsConnectRequestTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AwsConnectRequest>(
      row,
      columns: columns?.call(AwsConnectRequest.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AwsConnectRequest] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AwsConnectRequest?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AwsConnectRequestUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AwsConnectRequest>(
      id,
      columnValues: columnValues(AwsConnectRequest.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AwsConnectRequest]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AwsConnectRequest>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AwsConnectRequestUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<AwsConnectRequestTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AwsConnectRequestTable>? orderBy,
    _is.OrderByListBuilder<AwsConnectRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AwsConnectRequest>(
      columnValues: columnValues(AwsConnectRequest.t.updateTable),
      where: where(AwsConnectRequest.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AwsConnectRequest.t),
      orderByList: orderByList?.call(AwsConnectRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AwsConnectRequest]s in the list and returns the deleted rows.
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
  Future<List<AwsConnectRequest>> delete(
    _is.DatabaseSession session,
    List<AwsConnectRequest> rows, {
    _is.OrderByBuilder<AwsConnectRequestTable>? orderBy,
    _is.OrderByListBuilder<AwsConnectRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AwsConnectRequest>(
      rows,
      orderBy: orderBy?.call(AwsConnectRequest.t),
      orderByList: orderByList?.call(AwsConnectRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AwsConnectRequest].
  Future<AwsConnectRequest> deleteRow(
    _is.DatabaseSession session,
    AwsConnectRequest row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AwsConnectRequest>(
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
  Future<List<AwsConnectRequest>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AwsConnectRequestTable> where,
    _is.OrderByBuilder<AwsConnectRequestTable>? orderBy,
    _is.OrderByListBuilder<AwsConnectRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AwsConnectRequest>(
      where: where(AwsConnectRequest.t),
      orderBy: orderBy?.call(AwsConnectRequest.t),
      orderByList: orderByList?.call(AwsConnectRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AwsConnectRequestTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AwsConnectRequest>(
      where: where?.call(AwsConnectRequest.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AwsConnectRequest] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AwsConnectRequestTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AwsConnectRequest>(
      where: where(AwsConnectRequest.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
