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
import '../../workspace/models/workspace.dart' as _ikenbmzt;
import '../../workspace/models/workspace_role.dart' as _iwddgb3z;

abstract class WorkspaceMember
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  WorkspaceMember._({
    this.id,
    required this.workspaceId,
    this.workspace,
    required this.email,
    required this.role,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory WorkspaceMember({
    int? id,
    required int workspaceId,
    _ikenbmzt.Workspace? workspace,
    required String email,
    required _iwddgb3z.WorkspaceRole role,
    DateTime? createdAt,
  }) = _WorkspaceMemberImpl;

  factory WorkspaceMember.fromJson(Map<String, dynamic> jsonSerialization) {
    return WorkspaceMember(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      workspace: jsonSerialization['workspace'] == null
          ? null
          : _itytg29z.Protocol().deserialize<_ikenbmzt.Workspace>(
              jsonSerialization['workspace'],
            ),
      email: jsonSerialization['email'] as String,
      role: _iwddgb3z.WorkspaceRole.fromJson(
        (jsonSerialization['role'] as String),
      ),
      createdAt: jsonSerialization['createdAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  static final t = WorkspaceMemberTable();

  static const db = WorkspaceMemberRepository._();

  @override
  int? id;

  int workspaceId;

  _ikenbmzt.Workspace? workspace;

  /// Lowercase email. The person signs in with it.
  String email;

  _iwddgb3z.WorkspaceRole role;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [WorkspaceMember]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  WorkspaceMember copyWith({
    int? id,
    int? workspaceId,
    _ikenbmzt.Workspace? workspace,
    String? email,
    _iwddgb3z.WorkspaceRole? role,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'WorkspaceMember',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      if (workspace != null) 'workspace': workspace?.toJson(),
      'email': email,
      'role': role.toJson(),
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'WorkspaceMember',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      if (workspace != null) 'workspace': workspace?.toJsonForProtocol(),
      'email': email,
      'role': role.toJson(),
      'createdAt': createdAt.toJson(),
    };
  }

  static WorkspaceMemberInclude include({
    _ikenbmzt.WorkspaceInclude? workspace,
  }) {
    return WorkspaceMemberInclude._(workspace: workspace);
  }

  static WorkspaceMemberIncludeList includeList({
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<WorkspaceMemberTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceMemberTable>? orderByList,
    WorkspaceMemberInclude? include,
  }) {
    return WorkspaceMemberIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(WorkspaceMember.t),
      orderByList: orderByList?.call(WorkspaceMember.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _WorkspaceMemberImpl extends WorkspaceMember {
  _WorkspaceMemberImpl({
    int? id,
    required int workspaceId,
    _ikenbmzt.Workspace? workspace,
    required String email,
    required _iwddgb3z.WorkspaceRole role,
    DateTime? createdAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         workspace: workspace,
         email: email,
         role: role,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [WorkspaceMember]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  WorkspaceMember copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    Object? workspace = _Undefined,
    String? email,
    _iwddgb3z.WorkspaceRole? role,
    DateTime? createdAt,
  }) {
    return WorkspaceMember(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      workspace: workspace is _ikenbmzt.Workspace?
          ? workspace
          : this.workspace?.copyWith(),
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class WorkspaceMemberUpdateTable extends _is.UpdateTable<WorkspaceMemberTable> {
  WorkspaceMemberUpdateTable(super.table);

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> email(String value) => _is.ColumnValue(
    table.email,
    value,
  );

  _is.ColumnValue<_iwddgb3z.WorkspaceRole, _iwddgb3z.WorkspaceRole> role(
    _iwddgb3z.WorkspaceRole value,
  ) => _is.ColumnValue(
    table.role,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class WorkspaceMemberTable extends _is.Table<int?> {
  WorkspaceMemberTable({super.tableRelation})
    : super(tableName: 'workspace_member') {
    updateTable = WorkspaceMemberUpdateTable(this);
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    email = _is.ColumnString(
      'email',
      this,
    );
    role = _is.ColumnEnum(
      'role',
      this,
      _is.EnumSerialization.byName,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
      hasDefault: true,
    );
  }

  late final WorkspaceMemberUpdateTable updateTable;

  late final _is.ColumnInt workspaceId;

  _ikenbmzt.WorkspaceTable? _workspace;

  /// Lowercase email. The person signs in with it.
  late final _is.ColumnString email;

  late final _is.ColumnEnum<_iwddgb3z.WorkspaceRole> role;

  late final _is.ColumnDateTime createdAt;

  _ikenbmzt.WorkspaceTable get workspace {
    if (_workspace != null) return _workspace!;
    _workspace = _is.createRelationTable(
      relationFieldName: 'workspace',
      field: WorkspaceMember.t.workspaceId,
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
    email,
    role,
    createdAt,
  ];

  @override
  _is.Table? getRelationTable(String relationField) {
    if (relationField == 'workspace') {
      return workspace;
    }
    return null;
  }
}

class WorkspaceMemberInclude extends _is.IncludeObject {
  WorkspaceMemberInclude._({_ikenbmzt.WorkspaceInclude? workspace}) {
    _workspace = workspace;
  }

  _ikenbmzt.WorkspaceInclude? _workspace;

  @override
  Map<String, _is.Include?> get includes => {'workspace': _workspace};

  @override
  _is.Table<int?> get table => WorkspaceMember.t;
}

class WorkspaceMemberIncludeList extends _is.IncludeList {
  WorkspaceMemberIncludeList._({
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(WorkspaceMember.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => WorkspaceMember.t;
}

class WorkspaceMemberRepository {
  const WorkspaceMemberRepository._();

  final attachRow = const WorkspaceMemberAttachRowRepository._();

  /// Returns a list of [WorkspaceMember]s matching the given query parameters.
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
  Future<List<WorkspaceMember>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<WorkspaceMemberTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceMemberTable>? orderByList,
    _is.Transaction? transaction,
    WorkspaceMemberInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<WorkspaceMember>(
      where: where?.call(WorkspaceMember.t),
      orderBy: orderBy?.call(WorkspaceMember.t),
      orderByList: orderByList?.call(WorkspaceMember.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [WorkspaceMember] matching the given query parameters.
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
  Future<WorkspaceMember?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? where,
    int? offset,
    _is.OrderByBuilder<WorkspaceMemberTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceMemberTable>? orderByList,
    _is.Transaction? transaction,
    WorkspaceMemberInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<WorkspaceMember>(
      where: where?.call(WorkspaceMember.t),
      orderBy: orderBy?.call(WorkspaceMember.t),
      orderByList: orderByList?.call(WorkspaceMember.t),
      offset: offset,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [WorkspaceMember] by its [id] or null if no such row exists.
  Future<WorkspaceMember?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    WorkspaceMemberInclude? include,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<WorkspaceMember>(
      id,
      transaction: transaction,
      include: include,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [WorkspaceMember]s in the list and returns the inserted rows.
  ///
  /// The returned [WorkspaceMember]s will have their `id` fields set.
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
  Future<List<WorkspaceMember>> insert(
    _is.DatabaseSession session,
    List<WorkspaceMember> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<WorkspaceMember>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [WorkspaceMember] and returns the inserted row.
  ///
  /// The returned [WorkspaceMember] will have its `id` field set.
  Future<WorkspaceMember> insertRow(
    _is.DatabaseSession session,
    WorkspaceMember row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<WorkspaceMember>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [WorkspaceMember]s in the list and returns the resulting rows.
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
  /// The returned [WorkspaceMember]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<WorkspaceMember>> upsert(
    _is.DatabaseSession session,
    List<WorkspaceMember> rows, {
    required _is.ColumnSelections<WorkspaceMemberTable> conflictColumns,
    _is.ColumnSelections<WorkspaceMemberTable>? updateColumns,
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<WorkspaceMember>(
      rows,
      conflictColumns: conflictColumns(WorkspaceMember.t),
      updateColumns: updateColumns?.call(WorkspaceMember.t),
      updateWhere: updateWhere?.call(WorkspaceMember.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [WorkspaceMember] and returns the resulting row.
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
  /// The returned [WorkspaceMember] will have its `id` field set.
  Future<WorkspaceMember?> upsertRow(
    _is.DatabaseSession session,
    WorkspaceMember row, {
    required _is.ColumnSelections<WorkspaceMemberTable> conflictColumns,
    _is.ColumnSelections<WorkspaceMemberTable>? updateColumns,
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<WorkspaceMember>(
      row,
      conflictColumns: conflictColumns(WorkspaceMember.t),
      updateColumns: updateColumns?.call(WorkspaceMember.t),
      updateWhere: updateWhere?.call(WorkspaceMember.t),
      transaction: transaction,
    );
  }

  /// Updates all [WorkspaceMember]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<WorkspaceMember>> update(
    _is.DatabaseSession session,
    List<WorkspaceMember> rows, {
    _is.ColumnSelections<WorkspaceMemberTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<WorkspaceMember>(
      rows,
      columns: columns?.call(WorkspaceMember.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [WorkspaceMember]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<WorkspaceMember> updateRow(
    _is.DatabaseSession session,
    WorkspaceMember row, {
    _is.ColumnSelections<WorkspaceMemberTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<WorkspaceMember>(
      row,
      columns: columns?.call(WorkspaceMember.t),
      transaction: transaction,
    );
  }

  /// Updates a single [WorkspaceMember] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<WorkspaceMember?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<WorkspaceMemberUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<WorkspaceMember>(
      id,
      columnValues: columnValues(WorkspaceMember.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [WorkspaceMember]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<WorkspaceMember>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<WorkspaceMemberUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<WorkspaceMemberTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<WorkspaceMemberTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceMemberTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<WorkspaceMember>(
      columnValues: columnValues(WorkspaceMember.t.updateTable),
      where: where(WorkspaceMember.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(WorkspaceMember.t),
      orderByList: orderByList?.call(WorkspaceMember.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [WorkspaceMember]s in the list and returns the deleted rows.
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
  Future<List<WorkspaceMember>> delete(
    _is.DatabaseSession session,
    List<WorkspaceMember> rows, {
    _is.OrderByBuilder<WorkspaceMemberTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceMemberTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<WorkspaceMember>(
      rows,
      orderBy: orderBy?.call(WorkspaceMember.t),
      orderByList: orderByList?.call(WorkspaceMember.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [WorkspaceMember].
  Future<WorkspaceMember> deleteRow(
    _is.DatabaseSession session,
    WorkspaceMember row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<WorkspaceMember>(
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
  Future<List<WorkspaceMember>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<WorkspaceMemberTable> where,
    _is.OrderByBuilder<WorkspaceMemberTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceMemberTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<WorkspaceMember>(
      where: where(WorkspaceMember.t),
      orderBy: orderBy?.call(WorkspaceMember.t),
      orderByList: orderByList?.call(WorkspaceMember.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<WorkspaceMemberTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<WorkspaceMember>(
      where: where?.call(WorkspaceMember.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [WorkspaceMember] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<WorkspaceMemberTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<WorkspaceMember>(
      where: where(WorkspaceMember.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}

class WorkspaceMemberAttachRowRepository {
  const WorkspaceMemberAttachRowRepository._();

  /// Creates a relation between the given [WorkspaceMember] and [Workspace]
  /// by setting the [WorkspaceMember]'s foreign key `workspaceId` to refer to the [Workspace].
  Future<void> workspace(
    _is.DatabaseSession session,
    WorkspaceMember workspaceMember,
    _ikenbmzt.Workspace workspace, {
    _is.Transaction? transaction,
  }) async {
    if (workspaceMember.id == null) {
      throw ArgumentError.notNull('workspaceMember.id');
    }
    if (workspace.id == null) {
      throw ArgumentError.notNull('workspace.id');
    }

    var $workspaceMember = workspaceMember.copyWith(workspaceId: workspace.id);
    await session.db.updateRow<WorkspaceMember>(
      $workspaceMember,
      columns: [WorkspaceMember.t.workspaceId],
      transaction: transaction,
    );
  }
}
