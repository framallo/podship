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

/// A pending 6-digit code. Never stores the code in clear.
abstract class EmailCodeRequest
    implements _is.TableRow<_is.UuidValue?>, _is.ProtocolSerialization {
  EmailCodeRequest._({
    this.id,
    required this.email,
    required this.codeHash,
    required this.expiresAt,
    int? attempts,
    this.consumedAt,
    String? locale,
    DateTime? createdAt,
  }) : attempts = attempts ?? 0,
       locale = locale ?? 'en',
       createdAt = createdAt ?? DateTime.now();

  factory EmailCodeRequest({
    _is.UuidValue? id,
    required String email,
    required String codeHash,
    required DateTime expiresAt,
    int? attempts,
    DateTime? consumedAt,
    String? locale,
    DateTime? createdAt,
  }) = _EmailCodeRequestImpl;

  factory EmailCodeRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return EmailCodeRequest(
      id: jsonSerialization['id'] == null
          ? null
          : _is.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      email: jsonSerialization['email'] as String,
      codeHash: jsonSerialization['codeHash'] as String,
      expiresAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['expiresAt'],
      ),
      attempts: jsonSerialization['attempts'] as int?,
      consumedAt: jsonSerialization['consumedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['consumedAt']),
      locale: jsonSerialization['locale'] as String?,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  static final t = EmailCodeRequestTable();

  static const db = EmailCodeRequestRepository._();

  @override
  _is.UuidValue? id;

  String email;

  /// Argon2 hash of the code.
  String codeHash;

  DateTime expiresAt;

  int attempts;

  DateTime? consumedAt;

  String locale;

  DateTime createdAt;

  @override
  _is.Table<_is.UuidValue?> get table => t;

  /// Returns a shallow copy of this [EmailCodeRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  EmailCodeRequest copyWith({
    _is.UuidValue? id,
    String? email,
    String? codeHash,
    DateTime? expiresAt,
    int? attempts,
    DateTime? consumedAt,
    String? locale,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EmailCodeRequest',
      if (id != null) 'id': id?.toJson(),
      'email': email,
      'codeHash': codeHash,
      'expiresAt': expiresAt.toJson(),
      'attempts': attempts,
      if (consumedAt != null) 'consumedAt': consumedAt?.toJson(),
      'locale': locale,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static EmailCodeRequestInclude include() {
    return EmailCodeRequestInclude._();
  }

  static EmailCodeRequestIncludeList includeList({
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EmailCodeRequestTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeRequestTable>? orderByList,
    EmailCodeRequestInclude? include,
  }) {
    return EmailCodeRequestIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EmailCodeRequest.t),
      orderByList: orderByList?.call(EmailCodeRequest.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _EmailCodeRequestImpl extends EmailCodeRequest {
  _EmailCodeRequestImpl({
    _is.UuidValue? id,
    required String email,
    required String codeHash,
    required DateTime expiresAt,
    int? attempts,
    DateTime? consumedAt,
    String? locale,
    DateTime? createdAt,
  }) : super._(
         id: id,
         email: email,
         codeHash: codeHash,
         expiresAt: expiresAt,
         attempts: attempts,
         consumedAt: consumedAt,
         locale: locale,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [EmailCodeRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  EmailCodeRequest copyWith({
    Object? id = _Undefined,
    String? email,
    String? codeHash,
    DateTime? expiresAt,
    int? attempts,
    Object? consumedAt = _Undefined,
    String? locale,
    DateTime? createdAt,
  }) {
    return EmailCodeRequest(
      id: id is _is.UuidValue? ? id : this.id,
      email: email ?? this.email,
      codeHash: codeHash ?? this.codeHash,
      expiresAt: expiresAt ?? this.expiresAt,
      attempts: attempts ?? this.attempts,
      consumedAt: consumedAt is DateTime? ? consumedAt : this.consumedAt,
      locale: locale ?? this.locale,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class EmailCodeRequestUpdateTable
    extends _is.UpdateTable<EmailCodeRequestTable> {
  EmailCodeRequestUpdateTable(super.table);

  _is.ColumnValue<String, String> email(String value) => _is.ColumnValue(
    table.email,
    value,
  );

  _is.ColumnValue<String, String> codeHash(String value) => _is.ColumnValue(
    table.codeHash,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> expiresAt(DateTime value) =>
      _is.ColumnValue(
        table.expiresAt,
        value,
      );

  _is.ColumnValue<int, int> attempts(int value) => _is.ColumnValue(
    table.attempts,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> consumedAt(DateTime? value) =>
      _is.ColumnValue(
        table.consumedAt,
        value,
      );

  _is.ColumnValue<String, String> locale(String value) => _is.ColumnValue(
    table.locale,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class EmailCodeRequestTable extends _is.Table<_is.UuidValue?> {
  EmailCodeRequestTable({super.tableRelation})
    : super(tableName: 'email_code_request') {
    updateTable = EmailCodeRequestUpdateTable(this);
    email = _is.ColumnString(
      'email',
      this,
    );
    codeHash = _is.ColumnString(
      'codeHash',
      this,
    );
    expiresAt = _is.ColumnDateTime(
      'expiresAt',
      this,
    );
    attempts = _is.ColumnInt(
      'attempts',
      this,
      hasDefault: true,
    );
    consumedAt = _is.ColumnDateTime(
      'consumedAt',
      this,
    );
    locale = _is.ColumnString(
      'locale',
      this,
      hasDefault: true,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
      hasDefault: true,
    );
  }

  late final EmailCodeRequestUpdateTable updateTable;

  late final _is.ColumnString email;

  /// Argon2 hash of the code.
  late final _is.ColumnString codeHash;

  late final _is.ColumnDateTime expiresAt;

  late final _is.ColumnInt attempts;

  late final _is.ColumnDateTime consumedAt;

  late final _is.ColumnString locale;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    email,
    codeHash,
    expiresAt,
    attempts,
    consumedAt,
    locale,
    createdAt,
  ];
}

class EmailCodeRequestInclude extends _is.IncludeObject {
  EmailCodeRequestInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<_is.UuidValue?> get table => EmailCodeRequest.t;
}

class EmailCodeRequestIncludeList extends _is.IncludeList {
  EmailCodeRequestIncludeList._({
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(EmailCodeRequest.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<_is.UuidValue?> get table => EmailCodeRequest.t;
}

class EmailCodeRequestRepository {
  const EmailCodeRequestRepository._();

  /// Returns a list of [EmailCodeRequest]s matching the given query parameters.
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
  Future<List<EmailCodeRequest>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EmailCodeRequestTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeRequestTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<EmailCodeRequest>(
      where: where?.call(EmailCodeRequest.t),
      orderBy: orderBy?.call(EmailCodeRequest.t),
      orderByList: orderByList?.call(EmailCodeRequest.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [EmailCodeRequest] matching the given query parameters.
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
  Future<EmailCodeRequest?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? where,
    int? offset,
    _is.OrderByBuilder<EmailCodeRequestTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeRequestTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<EmailCodeRequest>(
      where: where?.call(EmailCodeRequest.t),
      orderBy: orderBy?.call(EmailCodeRequest.t),
      orderByList: orderByList?.call(EmailCodeRequest.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [EmailCodeRequest] by its [id] or null if no such row exists.
  Future<EmailCodeRequest?> findById(
    _is.DatabaseSession session,
    _is.UuidValue id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<EmailCodeRequest>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [EmailCodeRequest]s in the list and returns the inserted rows.
  ///
  /// The returned [EmailCodeRequest]s will have their `id` fields set.
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
  Future<List<EmailCodeRequest>> insert(
    _is.DatabaseSession session,
    List<EmailCodeRequest> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<EmailCodeRequest>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [EmailCodeRequest] and returns the inserted row.
  ///
  /// The returned [EmailCodeRequest] will have its `id` field set.
  Future<EmailCodeRequest> insertRow(
    _is.DatabaseSession session,
    EmailCodeRequest row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<EmailCodeRequest>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [EmailCodeRequest]s in the list and returns the resulting rows.
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
  /// The returned [EmailCodeRequest]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EmailCodeRequest>> upsert(
    _is.DatabaseSession session,
    List<EmailCodeRequest> rows, {
    required _is.ColumnSelections<EmailCodeRequestTable> conflictColumns,
    _is.ColumnSelections<EmailCodeRequestTable>? updateColumns,
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<EmailCodeRequest>(
      rows,
      conflictColumns: conflictColumns(EmailCodeRequest.t),
      updateColumns: updateColumns?.call(EmailCodeRequest.t),
      updateWhere: updateWhere?.call(EmailCodeRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [EmailCodeRequest] and returns the resulting row.
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
  /// The returned [EmailCodeRequest] will have its `id` field set.
  Future<EmailCodeRequest?> upsertRow(
    _is.DatabaseSession session,
    EmailCodeRequest row, {
    required _is.ColumnSelections<EmailCodeRequestTable> conflictColumns,
    _is.ColumnSelections<EmailCodeRequestTable>? updateColumns,
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<EmailCodeRequest>(
      row,
      conflictColumns: conflictColumns(EmailCodeRequest.t),
      updateColumns: updateColumns?.call(EmailCodeRequest.t),
      updateWhere: updateWhere?.call(EmailCodeRequest.t),
      transaction: transaction,
    );
  }

  /// Updates all [EmailCodeRequest]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EmailCodeRequest>> update(
    _is.DatabaseSession session,
    List<EmailCodeRequest> rows, {
    _is.ColumnSelections<EmailCodeRequestTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<EmailCodeRequest>(
      rows,
      columns: columns?.call(EmailCodeRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [EmailCodeRequest]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<EmailCodeRequest> updateRow(
    _is.DatabaseSession session,
    EmailCodeRequest row, {
    _is.ColumnSelections<EmailCodeRequestTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<EmailCodeRequest>(
      row,
      columns: columns?.call(EmailCodeRequest.t),
      transaction: transaction,
    );
  }

  /// Updates a single [EmailCodeRequest] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<EmailCodeRequest?> updateById(
    _is.DatabaseSession session,
    _is.UuidValue id, {
    required _is.ColumnValueListBuilder<EmailCodeRequestUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<EmailCodeRequest>(
      id,
      columnValues: columnValues(EmailCodeRequest.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [EmailCodeRequest]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EmailCodeRequest>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<EmailCodeRequestUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<EmailCodeRequestTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EmailCodeRequestTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<EmailCodeRequest>(
      columnValues: columnValues(EmailCodeRequest.t.updateTable),
      where: where(EmailCodeRequest.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EmailCodeRequest.t),
      orderByList: orderByList?.call(EmailCodeRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [EmailCodeRequest]s in the list and returns the deleted rows.
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
  Future<List<EmailCodeRequest>> delete(
    _is.DatabaseSession session,
    List<EmailCodeRequest> rows, {
    _is.OrderByBuilder<EmailCodeRequestTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<EmailCodeRequest>(
      rows,
      orderBy: orderBy?.call(EmailCodeRequest.t),
      orderByList: orderByList?.call(EmailCodeRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [EmailCodeRequest].
  Future<EmailCodeRequest> deleteRow(
    _is.DatabaseSession session,
    EmailCodeRequest row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<EmailCodeRequest>(
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
  Future<List<EmailCodeRequest>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<EmailCodeRequestTable> where,
    _is.OrderByBuilder<EmailCodeRequestTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<EmailCodeRequest>(
      where: where(EmailCodeRequest.t),
      orderBy: orderBy?.call(EmailCodeRequest.t),
      orderByList: orderByList?.call(EmailCodeRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EmailCodeRequestTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<EmailCodeRequest>(
      where: where?.call(EmailCodeRequest.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [EmailCodeRequest] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<EmailCodeRequestTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<EmailCodeRequest>(
      where: where(EmailCodeRequest.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
