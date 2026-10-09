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

/// A personal access token for the podship CLI (`podship login`). Only the
/// SHA-256 is stored.
abstract class AccessToken
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AccessToken._({
    this.id,
    required this.workspaceId,
    required this.email,
    required this.name,
    required this.tokenHash,
    DateTime? createdAt,
    required this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AccessToken({
    int? id,
    required int workspaceId,
    required String email,
    required String name,
    required String tokenHash,
    DateTime? createdAt,
    required DateTime expiresAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) = _AccessTokenImpl;

  factory AccessToken.fromJson(Map<String, dynamic> jsonSerialization) {
    return AccessToken(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      email: jsonSerialization['email'] as String,
      name: jsonSerialization['name'] as String,
      tokenHash: jsonSerialization['tokenHash'] as String,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
      expiresAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      lastUsedAt: jsonSerialization['lastUsedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['lastUsedAt']),
      revokedAt: jsonSerialization['revokedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['revokedAt']),
    );
  }

  static final t = AccessTokenTable();

  static const db = AccessTokenRepository._();

  @override
  int? id;

  int workspaceId;

  String email;

  String name;

  String tokenHash;

  DateTime createdAt;

  DateTime expiresAt;

  DateTime? lastUsedAt;

  DateTime? revokedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AccessToken]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AccessToken copyWith({
    int? id,
    int? workspaceId,
    String? email,
    String? name,
    String? tokenHash,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AccessToken',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      'email': email,
      'name': name,
      'tokenHash': tokenHash,
      'createdAt': createdAt.toJson(),
      'expiresAt': expiresAt.toJson(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt?.toJson(),
      if (revokedAt != null) 'revokedAt': revokedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AccessTokenInclude include() {
    return AccessTokenInclude._();
  }

  static AccessTokenIncludeList includeList({
    _is.WhereExpressionBuilder<AccessTokenTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AccessTokenTable>? orderBy,
    _is.OrderByListBuilder<AccessTokenTable>? orderByList,
    AccessTokenInclude? include,
  }) {
    return AccessTokenIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AccessToken.t),
      orderByList: orderByList?.call(AccessToken.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AccessTokenImpl extends AccessToken {
  _AccessTokenImpl({
    int? id,
    required int workspaceId,
    required String email,
    required String name,
    required String tokenHash,
    DateTime? createdAt,
    required DateTime expiresAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         email: email,
         name: name,
         tokenHash: tokenHash,
         createdAt: createdAt,
         expiresAt: expiresAt,
         lastUsedAt: lastUsedAt,
         revokedAt: revokedAt,
       );

  /// Returns a shallow copy of this [AccessToken]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AccessToken copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    String? email,
    String? name,
    String? tokenHash,
    DateTime? createdAt,
    DateTime? expiresAt,
    Object? lastUsedAt = _Undefined,
    Object? revokedAt = _Undefined,
  }) {
    return AccessToken(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      email: email ?? this.email,
      name: name ?? this.name,
      tokenHash: tokenHash ?? this.tokenHash,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastUsedAt: lastUsedAt is DateTime? ? lastUsedAt : this.lastUsedAt,
      revokedAt: revokedAt is DateTime? ? revokedAt : this.revokedAt,
    );
  }
}

class AccessTokenUpdateTable extends _is.UpdateTable<AccessTokenTable> {
  AccessTokenUpdateTable(super.table);

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> email(String value) => _is.ColumnValue(
    table.email,
    value,
  );

  _is.ColumnValue<String, String> name(String value) => _is.ColumnValue(
    table.name,
    value,
  );

  _is.ColumnValue<String, String> tokenHash(String value) => _is.ColumnValue(
    table.tokenHash,
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

  _is.ColumnValue<DateTime, DateTime> lastUsedAt(DateTime? value) =>
      _is.ColumnValue(
        table.lastUsedAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> revokedAt(DateTime? value) =>
      _is.ColumnValue(
        table.revokedAt,
        value,
      );
}

class AccessTokenTable extends _is.Table<int?> {
  AccessTokenTable({super.tableRelation}) : super(tableName: 'access_token') {
    updateTable = AccessTokenUpdateTable(this);
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    email = _is.ColumnString(
      'email',
      this,
    );
    name = _is.ColumnString(
      'name',
      this,
    );
    tokenHash = _is.ColumnString(
      'tokenHash',
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
    lastUsedAt = _is.ColumnDateTime(
      'lastUsedAt',
      this,
    );
    revokedAt = _is.ColumnDateTime(
      'revokedAt',
      this,
    );
  }

  late final AccessTokenUpdateTable updateTable;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnString email;

  late final _is.ColumnString name;

  late final _is.ColumnString tokenHash;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime expiresAt;

  late final _is.ColumnDateTime lastUsedAt;

  late final _is.ColumnDateTime revokedAt;

  @override
  List<_is.Column> get columns => [
    id,
    workspaceId,
    email,
    name,
    tokenHash,
    createdAt,
    expiresAt,
    lastUsedAt,
    revokedAt,
  ];
}

class AccessTokenInclude extends _is.IncludeObject {
  AccessTokenInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AccessToken.t;
}

class AccessTokenIncludeList extends _is.IncludeList {
  AccessTokenIncludeList._({
    _is.WhereExpressionBuilder<AccessTokenTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AccessToken.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AccessToken.t;
}

class AccessTokenRepository {
  const AccessTokenRepository._();

  /// Returns a list of [AccessToken]s matching the given query parameters.
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
  Future<List<AccessToken>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AccessTokenTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AccessTokenTable>? orderBy,
    _is.OrderByListBuilder<AccessTokenTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AccessToken>(
      where: where?.call(AccessToken.t),
      orderBy: orderBy?.call(AccessToken.t),
      orderByList: orderByList?.call(AccessToken.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AccessToken] matching the given query parameters.
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
  Future<AccessToken?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AccessTokenTable>? where,
    int? offset,
    _is.OrderByBuilder<AccessTokenTable>? orderBy,
    _is.OrderByListBuilder<AccessTokenTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AccessToken>(
      where: where?.call(AccessToken.t),
      orderBy: orderBy?.call(AccessToken.t),
      orderByList: orderByList?.call(AccessToken.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AccessToken] by its [id] or null if no such row exists.
  Future<AccessToken?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AccessToken>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AccessToken]s in the list and returns the inserted rows.
  ///
  /// The returned [AccessToken]s will have their `id` fields set.
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
  Future<List<AccessToken>> insert(
    _is.DatabaseSession session,
    List<AccessToken> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AccessToken>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AccessToken] and returns the inserted row.
  ///
  /// The returned [AccessToken] will have its `id` field set.
  Future<AccessToken> insertRow(
    _is.DatabaseSession session,
    AccessToken row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AccessToken>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AccessToken]s in the list and returns the resulting rows.
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
  /// The returned [AccessToken]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AccessToken>> upsert(
    _is.DatabaseSession session,
    List<AccessToken> rows, {
    required _is.ColumnSelections<AccessTokenTable> conflictColumns,
    _is.ColumnSelections<AccessTokenTable>? updateColumns,
    _is.WhereExpressionBuilder<AccessTokenTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AccessToken>(
      rows,
      conflictColumns: conflictColumns(AccessToken.t),
      updateColumns: updateColumns?.call(AccessToken.t),
      updateWhere: updateWhere?.call(AccessToken.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AccessToken] and returns the resulting row.
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
  /// The returned [AccessToken] will have its `id` field set.
  Future<AccessToken?> upsertRow(
    _is.DatabaseSession session,
    AccessToken row, {
    required _is.ColumnSelections<AccessTokenTable> conflictColumns,
    _is.ColumnSelections<AccessTokenTable>? updateColumns,
    _is.WhereExpressionBuilder<AccessTokenTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AccessToken>(
      row,
      conflictColumns: conflictColumns(AccessToken.t),
      updateColumns: updateColumns?.call(AccessToken.t),
      updateWhere: updateWhere?.call(AccessToken.t),
      transaction: transaction,
    );
  }

  /// Updates all [AccessToken]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AccessToken>> update(
    _is.DatabaseSession session,
    List<AccessToken> rows, {
    _is.ColumnSelections<AccessTokenTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AccessToken>(
      rows,
      columns: columns?.call(AccessToken.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AccessToken]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AccessToken> updateRow(
    _is.DatabaseSession session,
    AccessToken row, {
    _is.ColumnSelections<AccessTokenTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AccessToken>(
      row,
      columns: columns?.call(AccessToken.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AccessToken] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AccessToken?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AccessTokenUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AccessToken>(
      id,
      columnValues: columnValues(AccessToken.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AccessToken]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AccessToken>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AccessTokenUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AccessTokenTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AccessTokenTable>? orderBy,
    _is.OrderByListBuilder<AccessTokenTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AccessToken>(
      columnValues: columnValues(AccessToken.t.updateTable),
      where: where(AccessToken.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AccessToken.t),
      orderByList: orderByList?.call(AccessToken.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AccessToken]s in the list and returns the deleted rows.
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
  Future<List<AccessToken>> delete(
    _is.DatabaseSession session,
    List<AccessToken> rows, {
    _is.OrderByBuilder<AccessTokenTable>? orderBy,
    _is.OrderByListBuilder<AccessTokenTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AccessToken>(
      rows,
      orderBy: orderBy?.call(AccessToken.t),
      orderByList: orderByList?.call(AccessToken.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AccessToken].
  Future<AccessToken> deleteRow(
    _is.DatabaseSession session,
    AccessToken row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AccessToken>(
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
  Future<List<AccessToken>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AccessTokenTable> where,
    _is.OrderByBuilder<AccessTokenTable>? orderBy,
    _is.OrderByListBuilder<AccessTokenTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AccessToken>(
      where: where(AccessToken.t),
      orderBy: orderBy?.call(AccessToken.t),
      orderByList: orderByList?.call(AccessToken.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AccessTokenTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AccessToken>(
      where: where?.call(AccessToken.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AccessToken] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AccessTokenTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AccessToken>(
      where: where(AccessToken.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
