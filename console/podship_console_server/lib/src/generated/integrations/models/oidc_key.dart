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

/// The console's OIDC signing key (RS256). AWS trusts tokens signed with the
/// active key. Disconnecting AWS retires it (INT-16).
abstract class OidcKey
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  OidcKey._({
    this.id,
    required this.kid,
    required this.privateKey,
    required this.publicJwk,
    DateTime? createdAt,
    this.retiredAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory OidcKey({
    int? id,
    required String kid,
    required String privateKey,
    required String publicJwk,
    DateTime? createdAt,
    DateTime? retiredAt,
  }) = _OidcKeyImpl;

  factory OidcKey.fromJson(Map<String, dynamic> jsonSerialization) {
    return OidcKey(
      id: jsonSerialization['id'] as int?,
      kid: jsonSerialization['kid'] as String,
      privateKey: jsonSerialization['privateKey'] as String,
      publicJwk: jsonSerialization['publicJwk'] as String,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
      retiredAt: jsonSerialization['retiredAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['retiredAt']),
    );
  }

  static final t = OidcKeyTable();

  static const db = OidcKeyRepository._();

  @override
  int? id;

  String kid;

  /// Encrypted private key (JSON of the RSA numbers).
  String privateKey;

  /// Public JWK as JSON.
  String publicJwk;

  DateTime createdAt;

  DateTime? retiredAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [OidcKey]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  OidcKey copyWith({
    int? id,
    String? kid,
    String? privateKey,
    String? publicJwk,
    DateTime? createdAt,
    DateTime? retiredAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'OidcKey',
      if (id != null) 'id': id,
      'kid': kid,
      'privateKey': privateKey,
      'publicJwk': publicJwk,
      'createdAt': createdAt.toJson(),
      if (retiredAt != null) 'retiredAt': retiredAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static OidcKeyInclude include() {
    return OidcKeyInclude._();
  }

  static OidcKeyIncludeList includeList({
    _is.WhereExpressionBuilder<OidcKeyTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<OidcKeyTable>? orderBy,
    _is.OrderByListBuilder<OidcKeyTable>? orderByList,
    OidcKeyInclude? include,
  }) {
    return OidcKeyIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(OidcKey.t),
      orderByList: orderByList?.call(OidcKey.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _OidcKeyImpl extends OidcKey {
  _OidcKeyImpl({
    int? id,
    required String kid,
    required String privateKey,
    required String publicJwk,
    DateTime? createdAt,
    DateTime? retiredAt,
  }) : super._(
         id: id,
         kid: kid,
         privateKey: privateKey,
         publicJwk: publicJwk,
         createdAt: createdAt,
         retiredAt: retiredAt,
       );

  /// Returns a shallow copy of this [OidcKey]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  OidcKey copyWith({
    Object? id = _Undefined,
    String? kid,
    String? privateKey,
    String? publicJwk,
    DateTime? createdAt,
    Object? retiredAt = _Undefined,
  }) {
    return OidcKey(
      id: id is int? ? id : this.id,
      kid: kid ?? this.kid,
      privateKey: privateKey ?? this.privateKey,
      publicJwk: publicJwk ?? this.publicJwk,
      createdAt: createdAt ?? this.createdAt,
      retiredAt: retiredAt is DateTime? ? retiredAt : this.retiredAt,
    );
  }
}

class OidcKeyUpdateTable extends _is.UpdateTable<OidcKeyTable> {
  OidcKeyUpdateTable(super.table);

  _is.ColumnValue<String, String> kid(String value) => _is.ColumnValue(
    table.kid,
    value,
  );

  _is.ColumnValue<String, String> privateKey(String value) => _is.ColumnValue(
    table.privateKey,
    value,
  );

  _is.ColumnValue<String, String> publicJwk(String value) => _is.ColumnValue(
    table.publicJwk,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> retiredAt(DateTime? value) =>
      _is.ColumnValue(
        table.retiredAt,
        value,
      );
}

class OidcKeyTable extends _is.Table<int?> {
  OidcKeyTable({super.tableRelation}) : super(tableName: 'oidc_key') {
    updateTable = OidcKeyUpdateTable(this);
    kid = _is.ColumnString(
      'kid',
      this,
    );
    privateKey = _is.ColumnString(
      'privateKey',
      this,
    );
    publicJwk = _is.ColumnString(
      'publicJwk',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
      hasDefault: true,
    );
    retiredAt = _is.ColumnDateTime(
      'retiredAt',
      this,
    );
  }

  late final OidcKeyUpdateTable updateTable;

  late final _is.ColumnString kid;

  /// Encrypted private key (JSON of the RSA numbers).
  late final _is.ColumnString privateKey;

  /// Public JWK as JSON.
  late final _is.ColumnString publicJwk;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime retiredAt;

  @override
  List<_is.Column> get columns => [
    id,
    kid,
    privateKey,
    publicJwk,
    createdAt,
    retiredAt,
  ];
}

class OidcKeyInclude extends _is.IncludeObject {
  OidcKeyInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => OidcKey.t;
}

class OidcKeyIncludeList extends _is.IncludeList {
  OidcKeyIncludeList._({
    _is.WhereExpressionBuilder<OidcKeyTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(OidcKey.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => OidcKey.t;
}

class OidcKeyRepository {
  const OidcKeyRepository._();

  /// Returns a list of [OidcKey]s matching the given query parameters.
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
  Future<List<OidcKey>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<OidcKeyTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<OidcKeyTable>? orderBy,
    _is.OrderByListBuilder<OidcKeyTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<OidcKey>(
      where: where?.call(OidcKey.t),
      orderBy: orderBy?.call(OidcKey.t),
      orderByList: orderByList?.call(OidcKey.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [OidcKey] matching the given query parameters.
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
  Future<OidcKey?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<OidcKeyTable>? where,
    int? offset,
    _is.OrderByBuilder<OidcKeyTable>? orderBy,
    _is.OrderByListBuilder<OidcKeyTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<OidcKey>(
      where: where?.call(OidcKey.t),
      orderBy: orderBy?.call(OidcKey.t),
      orderByList: orderByList?.call(OidcKey.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [OidcKey] by its [id] or null if no such row exists.
  Future<OidcKey?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<OidcKey>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [OidcKey]s in the list and returns the inserted rows.
  ///
  /// The returned [OidcKey]s will have their `id` fields set.
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
  Future<List<OidcKey>> insert(
    _is.DatabaseSession session,
    List<OidcKey> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<OidcKey>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [OidcKey] and returns the inserted row.
  ///
  /// The returned [OidcKey] will have its `id` field set.
  Future<OidcKey> insertRow(
    _is.DatabaseSession session,
    OidcKey row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<OidcKey>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [OidcKey]s in the list and returns the resulting rows.
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
  /// The returned [OidcKey]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<OidcKey>> upsert(
    _is.DatabaseSession session,
    List<OidcKey> rows, {
    required _is.ColumnSelections<OidcKeyTable> conflictColumns,
    _is.ColumnSelections<OidcKeyTable>? updateColumns,
    _is.WhereExpressionBuilder<OidcKeyTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<OidcKey>(
      rows,
      conflictColumns: conflictColumns(OidcKey.t),
      updateColumns: updateColumns?.call(OidcKey.t),
      updateWhere: updateWhere?.call(OidcKey.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [OidcKey] and returns the resulting row.
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
  /// The returned [OidcKey] will have its `id` field set.
  Future<OidcKey?> upsertRow(
    _is.DatabaseSession session,
    OidcKey row, {
    required _is.ColumnSelections<OidcKeyTable> conflictColumns,
    _is.ColumnSelections<OidcKeyTable>? updateColumns,
    _is.WhereExpressionBuilder<OidcKeyTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<OidcKey>(
      row,
      conflictColumns: conflictColumns(OidcKey.t),
      updateColumns: updateColumns?.call(OidcKey.t),
      updateWhere: updateWhere?.call(OidcKey.t),
      transaction: transaction,
    );
  }

  /// Updates all [OidcKey]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<OidcKey>> update(
    _is.DatabaseSession session,
    List<OidcKey> rows, {
    _is.ColumnSelections<OidcKeyTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<OidcKey>(
      rows,
      columns: columns?.call(OidcKey.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [OidcKey]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<OidcKey> updateRow(
    _is.DatabaseSession session,
    OidcKey row, {
    _is.ColumnSelections<OidcKeyTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<OidcKey>(
      row,
      columns: columns?.call(OidcKey.t),
      transaction: transaction,
    );
  }

  /// Updates a single [OidcKey] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<OidcKey?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<OidcKeyUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<OidcKey>(
      id,
      columnValues: columnValues(OidcKey.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [OidcKey]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<OidcKey>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<OidcKeyUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<OidcKeyTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<OidcKeyTable>? orderBy,
    _is.OrderByListBuilder<OidcKeyTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<OidcKey>(
      columnValues: columnValues(OidcKey.t.updateTable),
      where: where(OidcKey.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(OidcKey.t),
      orderByList: orderByList?.call(OidcKey.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [OidcKey]s in the list and returns the deleted rows.
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
  Future<List<OidcKey>> delete(
    _is.DatabaseSession session,
    List<OidcKey> rows, {
    _is.OrderByBuilder<OidcKeyTable>? orderBy,
    _is.OrderByListBuilder<OidcKeyTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<OidcKey>(
      rows,
      orderBy: orderBy?.call(OidcKey.t),
      orderByList: orderByList?.call(OidcKey.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [OidcKey].
  Future<OidcKey> deleteRow(
    _is.DatabaseSession session,
    OidcKey row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<OidcKey>(
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
  Future<List<OidcKey>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<OidcKeyTable> where,
    _is.OrderByBuilder<OidcKeyTable>? orderBy,
    _is.OrderByListBuilder<OidcKeyTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<OidcKey>(
      where: where(OidcKey.t),
      orderBy: orderBy?.call(OidcKey.t),
      orderByList: orderByList?.call(OidcKey.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<OidcKeyTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<OidcKey>(
      where: where?.call(OidcKey.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [OidcKey] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<OidcKeyTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<OidcKey>(
      where: where(OidcKey.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
