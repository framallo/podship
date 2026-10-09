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
import 'package:serverpod_auth_core_server/serverpod_auth_core_server.dart'
    as _iacs;

/// A sign-in account: links an email address to an AuthUser.
abstract class EmailCodeAccount
    implements _is.TableRow<_is.UuidValue?>, _is.ProtocolSerialization {
  EmailCodeAccount._({
    this.id,
    required this.authUserId,
    this.authUser,
    required this.email,
    String? locale,
    DateTime? createdAt,
    this.lastLoginAt,
  }) : locale = locale ?? 'en',
       createdAt = createdAt ?? DateTime.now();

  factory EmailCodeAccount({
    _is.UuidValue? id,
    required _is.UuidValue authUserId,
    _iacs.AuthUser? authUser,
    required String email,
    String? locale,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) = _EmailCodeAccountImpl;

  factory EmailCodeAccount.fromJson(Map<String, dynamic> jsonSerialization) {
    return EmailCodeAccount(
      id: jsonSerialization['id'] == null
          ? null
          : _is.UuidValueJsonExtension.fromJson(jsonSerialization['id']),
      authUserId: _is.UuidValueJsonExtension.fromJson(
        jsonSerialization['authUserId'],
      ),
      authUser: jsonSerialization['authUser'] == null
          ? null
          : _itytg29z.Protocol().deserialize<_iacs.AuthUser>(
              jsonSerialization['authUser'],
            ),
      email: jsonSerialization['email'] as String,
      locale: jsonSerialization['locale'] as String?,
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
      lastLoginAt: jsonSerialization['lastLoginAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['lastLoginAt'],
            ),
    );
  }

  static final t = EmailCodeAccountTable();

  static const db = EmailCodeAccountRepository._();

  @override
  _is.UuidValue? id;

  _is.UuidValue authUserId;

  _iacs.AuthUser? authUser;

  /// Lowercase email.
  String email;

  /// `es-MX` or `en`.
  String locale;

  DateTime createdAt;

  DateTime? lastLoginAt;

  @override
  _is.Table<_is.UuidValue?> get table => t;

  /// Returns a shallow copy of this [EmailCodeAccount]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  EmailCodeAccount copyWith({
    _is.UuidValue? id,
    _is.UuidValue? authUserId,
    _iacs.AuthUser? authUser,
    String? email,
    String? locale,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EmailCodeAccount',
      if (id != null) 'id': id?.toJson(),
      'authUserId': authUserId.toJson(),
      if (authUser != null) 'authUser': authUser?.toJson(),
      'email': email,
      'locale': locale,
      'createdAt': createdAt.toJson(),
      if (lastLoginAt != null) 'lastLoginAt': lastLoginAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static EmailCodeAccountInclude include({_iacs.AuthUserInclude? authUser}) {
    return EmailCodeAccountInclude._(authUser: authUser);
  }

  static EmailCodeAccountIncludeList includeList({
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EmailCodeAccountTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeAccountTable>? orderByList,
    EmailCodeAccountInclude? include,
  }) {
    return EmailCodeAccountIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EmailCodeAccount.t),
      orderByList: orderByList?.call(EmailCodeAccount.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _EmailCodeAccountImpl extends EmailCodeAccount {
  _EmailCodeAccountImpl({
    _is.UuidValue? id,
    required _is.UuidValue authUserId,
    _iacs.AuthUser? authUser,
    required String email,
    String? locale,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) : super._(
         id: id,
         authUserId: authUserId,
         authUser: authUser,
         email: email,
         locale: locale,
         createdAt: createdAt,
         lastLoginAt: lastLoginAt,
       );

  /// Returns a shallow copy of this [EmailCodeAccount]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  EmailCodeAccount copyWith({
    Object? id = _Undefined,
    _is.UuidValue? authUserId,
    Object? authUser = _Undefined,
    String? email,
    String? locale,
    DateTime? createdAt,
    Object? lastLoginAt = _Undefined,
  }) {
    return EmailCodeAccount(
      id: id is _is.UuidValue? ? id : this.id,
      authUserId: authUserId ?? this.authUserId,
      authUser: authUser is _iacs.AuthUser?
          ? authUser
          : this.authUser?.copyWith(),
      email: email ?? this.email,
      locale: locale ?? this.locale,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt is DateTime? ? lastLoginAt : this.lastLoginAt,
    );
  }
}

class EmailCodeAccountUpdateTable
    extends _is.UpdateTable<EmailCodeAccountTable> {
  EmailCodeAccountUpdateTable(super.table);

  _is.ColumnValue<_is.UuidValue, _is.UuidValue> authUserId(
    _is.UuidValue value,
  ) => _is.ColumnValue(
    table.authUserId,
    value,
  );

  _is.ColumnValue<String, String> email(String value) => _is.ColumnValue(
    table.email,
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

  _is.ColumnValue<DateTime, DateTime> lastLoginAt(DateTime? value) =>
      _is.ColumnValue(
        table.lastLoginAt,
        value,
      );
}

class EmailCodeAccountTable extends _is.Table<_is.UuidValue?> {
  EmailCodeAccountTable({super.tableRelation})
    : super(tableName: 'email_code_account') {
    updateTable = EmailCodeAccountUpdateTable(this);
    authUserId = _is.ColumnUuid(
      'authUserId',
      this,
    );
    email = _is.ColumnString(
      'email',
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
    lastLoginAt = _is.ColumnDateTime(
      'lastLoginAt',
      this,
    );
  }

  late final EmailCodeAccountUpdateTable updateTable;

  late final _is.ColumnUuid authUserId;

  _iacs.AuthUserTable? _authUser;

  /// Lowercase email.
  late final _is.ColumnString email;

  /// `es-MX` or `en`.
  late final _is.ColumnString locale;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime lastLoginAt;

  _iacs.AuthUserTable get authUser {
    if (_authUser != null) return _authUser!;
    _authUser = _is.createRelationTable(
      relationFieldName: 'authUser',
      field: EmailCodeAccount.t.authUserId,
      foreignField: _iacs.AuthUser.t.id,
      tableRelation: tableRelation,
      createTable: (foreignTableRelation) =>
          _iacs.AuthUserTable(tableRelation: foreignTableRelation),
    );
    return _authUser!;
  }

  @override
  List<_is.Column> get columns => [
    id,
    authUserId,
    email,
    locale,
    createdAt,
    lastLoginAt,
  ];

  @override
  _is.Table? getRelationTable(String relationField) {
    if (relationField == 'authUser') {
      return authUser;
    }
    return null;
  }
}

class EmailCodeAccountInclude extends _is.IncludeObject {
  EmailCodeAccountInclude._({_iacs.AuthUserInclude? authUser}) {
    _authUser = authUser;
  }

  _iacs.AuthUserInclude? _authUser;

  @override
  Map<String, _is.Include?> get includes => {'authUser': _authUser};

  @override
  _is.Table<_is.UuidValue?> get table => EmailCodeAccount.t;
}

class EmailCodeAccountIncludeList extends _is.IncludeList {
  EmailCodeAccountIncludeList._({
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(EmailCodeAccount.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<_is.UuidValue?> get table => EmailCodeAccount.t;
}

class EmailCodeAccountRepository {
  const EmailCodeAccountRepository._();

  final attachRow = const EmailCodeAccountAttachRowRepository._();

  /// Returns a list of [EmailCodeAccount]s matching the given query parameters.
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
  Future<List<EmailCodeAccount>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EmailCodeAccountTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeAccountTable>? orderByList,
    _is.Transaction? transaction,
    EmailCodeAccountInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<EmailCodeAccount>(
      where: where?.call(EmailCodeAccount.t),
      orderBy: orderBy?.call(EmailCodeAccount.t),
      orderByList: orderByList?.call(EmailCodeAccount.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [EmailCodeAccount] matching the given query parameters.
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
  Future<EmailCodeAccount?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? where,
    int? offset,
    _is.OrderByBuilder<EmailCodeAccountTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeAccountTable>? orderByList,
    _is.Transaction? transaction,
    EmailCodeAccountInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<EmailCodeAccount>(
      where: where?.call(EmailCodeAccount.t),
      orderBy: orderBy?.call(EmailCodeAccount.t),
      orderByList: orderByList?.call(EmailCodeAccount.t),
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [EmailCodeAccount] by its [id] or null if no such row exists.
  Future<EmailCodeAccount?> findById(
    _is.DatabaseSession session,
    _is.UuidValue id, {
    _is.Transaction? transaction,
    EmailCodeAccountInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<EmailCodeAccount>(
      id,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [EmailCodeAccount]s in the list and returns the inserted rows.
  ///
  /// The returned [EmailCodeAccount]s will have their `id` fields set.
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
  Future<List<EmailCodeAccount>> insert(
    _is.DatabaseSession session,
    List<EmailCodeAccount> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<EmailCodeAccount>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [EmailCodeAccount] and returns the inserted row.
  ///
  /// The returned [EmailCodeAccount] will have its `id` field set.
  Future<EmailCodeAccount> insertRow(
    _is.DatabaseSession session,
    EmailCodeAccount row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<EmailCodeAccount>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [EmailCodeAccount]s in the list and returns the resulting rows.
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
  /// The returned [EmailCodeAccount]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EmailCodeAccount>> upsert(
    _is.DatabaseSession session,
    List<EmailCodeAccount> rows, {
    required _is.ColumnSelections<EmailCodeAccountTable> conflictColumns,
    _is.ColumnSelections<EmailCodeAccountTable>? updateColumns,
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<EmailCodeAccount>(
      rows,
      conflictColumns: conflictColumns(EmailCodeAccount.t),
      updateColumns: updateColumns?.call(EmailCodeAccount.t),
      updateWhere: updateWhere?.call(EmailCodeAccount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [EmailCodeAccount] and returns the resulting row.
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
  /// The returned [EmailCodeAccount] will have its `id` field set.
  Future<EmailCodeAccount?> upsertRow(
    _is.DatabaseSession session,
    EmailCodeAccount row, {
    required _is.ColumnSelections<EmailCodeAccountTable> conflictColumns,
    _is.ColumnSelections<EmailCodeAccountTable>? updateColumns,
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<EmailCodeAccount>(
      row,
      conflictColumns: conflictColumns(EmailCodeAccount.t),
      updateColumns: updateColumns?.call(EmailCodeAccount.t),
      updateWhere: updateWhere?.call(EmailCodeAccount.t),
      transaction: transaction,
    );
  }

  /// Updates all [EmailCodeAccount]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EmailCodeAccount>> update(
    _is.DatabaseSession session,
    List<EmailCodeAccount> rows, {
    _is.ColumnSelections<EmailCodeAccountTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<EmailCodeAccount>(
      rows,
      columns: columns?.call(EmailCodeAccount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [EmailCodeAccount]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<EmailCodeAccount> updateRow(
    _is.DatabaseSession session,
    EmailCodeAccount row, {
    _is.ColumnSelections<EmailCodeAccountTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<EmailCodeAccount>(
      row,
      columns: columns?.call(EmailCodeAccount.t),
      transaction: transaction,
    );
  }

  /// Updates a single [EmailCodeAccount] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<EmailCodeAccount?> updateById(
    _is.DatabaseSession session,
    _is.UuidValue id, {
    required _is.ColumnValueListBuilder<EmailCodeAccountUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<EmailCodeAccount>(
      id,
      columnValues: columnValues(EmailCodeAccount.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [EmailCodeAccount]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EmailCodeAccount>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<EmailCodeAccountUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<EmailCodeAccountTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EmailCodeAccountTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeAccountTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<EmailCodeAccount>(
      columnValues: columnValues(EmailCodeAccount.t.updateTable),
      where: where(EmailCodeAccount.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EmailCodeAccount.t),
      orderByList: orderByList?.call(EmailCodeAccount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [EmailCodeAccount]s in the list and returns the deleted rows.
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
  Future<List<EmailCodeAccount>> delete(
    _is.DatabaseSession session,
    List<EmailCodeAccount> rows, {
    _is.OrderByBuilder<EmailCodeAccountTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeAccountTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<EmailCodeAccount>(
      rows,
      orderBy: orderBy?.call(EmailCodeAccount.t),
      orderByList: orderByList?.call(EmailCodeAccount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [EmailCodeAccount].
  Future<EmailCodeAccount> deleteRow(
    _is.DatabaseSession session,
    EmailCodeAccount row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<EmailCodeAccount>(
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
  Future<List<EmailCodeAccount>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<EmailCodeAccountTable> where,
    _is.OrderByBuilder<EmailCodeAccountTable>? orderBy,
    _is.OrderByListBuilder<EmailCodeAccountTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<EmailCodeAccount>(
      where: where(EmailCodeAccount.t),
      orderBy: orderBy?.call(EmailCodeAccount.t),
      orderByList: orderByList?.call(EmailCodeAccount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EmailCodeAccountTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<EmailCodeAccount>(
      where: where?.call(EmailCodeAccount.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [EmailCodeAccount] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<EmailCodeAccountTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<EmailCodeAccount>(
      where: where(EmailCodeAccount.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}

class EmailCodeAccountAttachRowRepository {
  const EmailCodeAccountAttachRowRepository._();

  /// Creates a relation between the given [EmailCodeAccount] and [AuthUser]
  /// by setting the [EmailCodeAccount]'s foreign key `authUserId` to refer to the [AuthUser].
  Future<void> authUser(
    _is.DatabaseSession session,
    EmailCodeAccount emailCodeAccount,
    _iacs.AuthUser authUser, {
    _is.Transaction? transaction,
  }) async {
    if (emailCodeAccount.id == null) {
      throw ArgumentError.notNull('emailCodeAccount.id');
    }
    if (authUser.id == null) {
      throw ArgumentError.notNull('authUser.id');
    }

    var $emailCodeAccount = emailCodeAccount.copyWith(authUserId: authUser.id);
    await session.db.updateRow<EmailCodeAccount>(
      $emailCodeAccount,
      columns: [EmailCodeAccount.t.authUserId],
      transaction: transaction,
    );
  }
}
