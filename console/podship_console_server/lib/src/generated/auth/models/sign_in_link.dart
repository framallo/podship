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

/// A one-time sign-in link, made on the server (`/internal/sign-in-link`).
abstract class SignInLink
    implements _is.TableRow<_is.UuidValue?>, _is.ProtocolSerialization {
  SignInLink._({
    this.id,
    required this.email,
    required this.tokenHash,
    required this.expiresAt,
    this.consumedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory SignInLink({
    _is.UuidValue? id,
    required String email,
    required String tokenHash,
    required DateTime expiresAt,
    DateTime? consumedAt,
    DateTime? createdAt,
  }) = _SignInLinkImpl;

  factory SignInLink.fromJson(Map<String, dynamic> jsonSerialization) {
    return SignInLink(
      id: jsonSerialization['id'] == null
          ? null
          : _is.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      email: jsonSerialization['email'] as String,
      tokenHash: jsonSerialization['tokenHash'] as String,
      expiresAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      consumedAt: jsonSerialization['consumedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['consumedAt']),
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  static final t = SignInLinkTable();

  static const db = SignInLinkRepository._();

  @override
  _is.UuidValue? id;

  String email;

  /// SHA-256 of the token in the link.
  String tokenHash;

  DateTime expiresAt;

  DateTime? consumedAt;

  DateTime createdAt;

  @override
  _is.Table<_is.UuidValue?> get table => t;

  /// Returns a shallow copy of this [SignInLink]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  SignInLink copyWith({
    _is.UuidValue? id,
    String? email,
    String? tokenHash,
    DateTime? expiresAt,
    DateTime? consumedAt,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SignInLink',
      if (id != null) 'id': id?.toJson(),
      'email': email,
      'tokenHash': tokenHash,
      'expiresAt': expiresAt.toJson(),
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static SignInLinkInclude include() {
    return SignInLinkInclude._();
  }

  static SignInLinkIncludeList includeList({
    _is.WhereExpressionBuilder<SignInLinkTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<SignInLinkTable>? orderBy,
    _is.OrderByListBuilder<SignInLinkTable>? orderByList,
    SignInLinkInclude? include,
  }) {
    return SignInLinkIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(SignInLink.t),
      orderByList: orderByList?.call(SignInLink.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _SignInLinkImpl extends SignInLink {
  _SignInLinkImpl({
    _is.UuidValue? id,
    required String email,
    required String tokenHash,
    required DateTime expiresAt,
    DateTime? consumedAt,
    DateTime? createdAt,
  }) : super._(
         id: id,
         email: email,
         tokenHash: tokenHash,
         expiresAt: expiresAt,
         consumedAt: consumedAt,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [SignInLink]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  SignInLink copyWith({
    Object? id = _Undefined,
    String? email,
    String? tokenHash,
    DateTime? expiresAt,
    Object? consumedAt = _Undefined,
    DateTime? createdAt,
  }) {
    return SignInLink(
      id: id is _is.UuidValue? ? id : this.id,
      email: email ?? this.email,
      tokenHash: tokenHash ?? this.tokenHash,
      expiresAt: expiresAt ?? this.expiresAt,
      consumedAt: consumedAt is DateTime? ? consumedAt : this.consumedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class SignInLinkUpdateTable extends _is.UpdateTable<SignInLinkTable> {
  SignInLinkUpdateTable(super.table);

  _is.ColumnValue<String, String> email(String value) => _is.ColumnValue(
    table.email,
    value,
  );

  _is.ColumnValue<String, String> tokenHash(String value) => _is.ColumnValue(
    table.tokenHash,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> expiresAt(DateTime value) =>
      _is.ColumnValue(
        table.expiresAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> consumedAt(DateTime? value) =>
      _is.ColumnValue(
        table.consumedAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class SignInLinkTable extends _is.Table<_is.UuidValue?> {
  SignInLinkTable({super.tableRelation}) : super(tableName: 'sign_in_link') {
    updateTable = SignInLinkUpdateTable(this);
    email = _is.ColumnString(
      'email',
      this,
    );
    tokenHash = _is.ColumnString(
      'tokenHash',
      this,
    );
    expiresAt = _is.ColumnDateTime(
      'expiresAt',
      this,
    );
    consumedAt = _is.ColumnDateTime(
      'consumedAt',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
      hasDefault: true,
    );
  }

  late final SignInLinkUpdateTable updateTable;

  late final _is.ColumnString email;

  /// SHA-256 of the token in the link.
  late final _is.ColumnString tokenHash;

  late final _is.ColumnDateTime expiresAt;

  late final _is.ColumnDateTime consumedAt;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    email,
    tokenHash,
    expiresAt,
    consumedAt,
    createdAt,
  ];
}

class SignInLinkInclude extends _is.IncludeObject {
  SignInLinkInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<_is.UuidValue?> get table => SignInLink.t;
}

class SignInLinkIncludeList extends _is.IncludeList {
  SignInLinkIncludeList._({
    _is.WhereExpressionBuilder<SignInLinkTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(SignInLink.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<_is.UuidValue?> get table => SignInLink.t;
}

class SignInLinkRepository {
  const SignInLinkRepository._();

  /// Returns a list of [SignInLink]s matching the given query parameters.
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
  Future<List<SignInLink>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<SignInLinkTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<SignInLinkTable>? orderBy,
    _is.OrderByListBuilder<SignInLinkTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<SignInLink>(
      where: where?.call(SignInLink.t),
      orderBy: orderBy?.call(SignInLink.t),
      orderByList: orderByList?.call(SignInLink.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [SignInLink] matching the given query parameters.
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
  Future<SignInLink?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<SignInLinkTable>? where,
    int? offset,
    _is.OrderByBuilder<SignInLinkTable>? orderBy,
    _is.OrderByListBuilder<SignInLinkTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<SignInLink>(
      where: where?.call(SignInLink.t),
      orderBy: orderBy?.call(SignInLink.t),
      orderByList: orderByList?.call(SignInLink.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [SignInLink] by its [id] or null if no such row exists.
  Future<SignInLink?> findById(
    _is.DatabaseSession session,
    _is.UuidValue id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<SignInLink>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [SignInLink]s in the list and returns the inserted rows.
  ///
  /// The returned [SignInLink]s will have their `id` fields set.
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
  Future<List<SignInLink>> insert(
    _is.DatabaseSession session,
    List<SignInLink> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<SignInLink>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [SignInLink] and returns the inserted row.
  ///
  /// The returned [SignInLink] will have its `id` field set.
  Future<SignInLink> insertRow(
    _is.DatabaseSession session,
    SignInLink row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<SignInLink>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [SignInLink]s in the list and returns the resulting rows.
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
  /// The returned [SignInLink]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<SignInLink>> upsert(
    _is.DatabaseSession session,
    List<SignInLink> rows, {
    required _is.ColumnSelections<SignInLinkTable> conflictColumns,
    _is.ColumnSelections<SignInLinkTable>? updateColumns,
    _is.WhereExpressionBuilder<SignInLinkTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<SignInLink>(
      rows,
      conflictColumns: conflictColumns(SignInLink.t),
      updateColumns: updateColumns?.call(SignInLink.t),
      updateWhere: updateWhere?.call(SignInLink.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [SignInLink] and returns the resulting row.
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
  /// The returned [SignInLink] will have its `id` field set.
  Future<SignInLink?> upsertRow(
    _is.DatabaseSession session,
    SignInLink row, {
    required _is.ColumnSelections<SignInLinkTable> conflictColumns,
    _is.ColumnSelections<SignInLinkTable>? updateColumns,
    _is.WhereExpressionBuilder<SignInLinkTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<SignInLink>(
      row,
      conflictColumns: conflictColumns(SignInLink.t),
      updateColumns: updateColumns?.call(SignInLink.t),
      updateWhere: updateWhere?.call(SignInLink.t),
      transaction: transaction,
    );
  }

  /// Updates all [SignInLink]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<SignInLink>> update(
    _is.DatabaseSession session,
    List<SignInLink> rows, {
    _is.ColumnSelections<SignInLinkTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<SignInLink>(
      rows,
      columns: columns?.call(SignInLink.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [SignInLink]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<SignInLink> updateRow(
    _is.DatabaseSession session,
    SignInLink row, {
    _is.ColumnSelections<SignInLinkTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<SignInLink>(
      row,
      columns: columns?.call(SignInLink.t),
      transaction: transaction,
    );
  }

  /// Updates a single [SignInLink] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<SignInLink?> updateById(
    _is.DatabaseSession session,
    _is.UuidValue id, {
    required _is.ColumnValueListBuilder<SignInLinkUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<SignInLink>(
      id,
      columnValues: columnValues(SignInLink.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [SignInLink]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<SignInLink>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<SignInLinkUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<SignInLinkTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<SignInLinkTable>? orderBy,
    _is.OrderByListBuilder<SignInLinkTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<SignInLink>(
      columnValues: columnValues(SignInLink.t.updateTable),
      where: where(SignInLink.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(SignInLink.t),
      orderByList: orderByList?.call(SignInLink.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [SignInLink]s in the list and returns the deleted rows.
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
  Future<List<SignInLink>> delete(
    _is.DatabaseSession session,
    List<SignInLink> rows, {
    _is.OrderByBuilder<SignInLinkTable>? orderBy,
    _is.OrderByListBuilder<SignInLinkTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<SignInLink>(
      rows,
      orderBy: orderBy?.call(SignInLink.t),
      orderByList: orderByList?.call(SignInLink.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [SignInLink].
  Future<SignInLink> deleteRow(
    _is.DatabaseSession session,
    SignInLink row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<SignInLink>(
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
  Future<List<SignInLink>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<SignInLinkTable> where,
    _is.OrderByBuilder<SignInLinkTable>? orderBy,
    _is.OrderByListBuilder<SignInLinkTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<SignInLink>(
      where: where(SignInLink.t),
      orderBy: orderBy?.call(SignInLink.t),
      orderByList: orderByList?.call(SignInLink.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<SignInLinkTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<SignInLink>(
      where: where?.call(SignInLink.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [SignInLink] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<SignInLinkTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<SignInLink>(
      where: where(SignInLink.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
