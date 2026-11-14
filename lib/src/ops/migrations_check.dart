// The destructive-migration check of a blue/green deploy.
//
// During a blue/green switch the old and the new release run against the
// same database: the new one applies its migrations while the old one
// still serves. A migration is safe only when the old code keeps working on
// the new schema (expand/contract). A migration that drops or renames a
// table or a column, changes a column type, or adds a NOT NULL column
// without a default breaks the old code, so a blue/green deploy stops on it.
// `deploy --allow-destructive-migrations` ships it in place instead (the
// old release stops before the new one migrates).
//
// The check reads Serverpod migrations: one folder per migration in
// `<server_package>/migrations/`, with `migration.sql` and
// `migration.json`. Serverpod's own warnings (`tableDropped`,
// `columnDropped`, `notNullAdded`) count, and so does the SQL, because a
// migration.sql can be edited by hand.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One reason a migration is not safe for blue/green.
class MigrationIssue {
  MigrationIssue(this.migration, this.reason);
  final String migration;
  final String reason;

  @override
  String toString() => '$migration: $reason';

  @override
  bool operator ==(Object other) =>
      other is MigrationIssue &&
      other.migration == migration &&
      other.reason == reason;
  @override
  int get hashCode => Object.hash(migration, reason);
}

/// The destructive statements of [sql]. Statements that create a table are
/// safe (the old code does not know the table); `serverpod_migrations`
/// bookkeeping is ignored.
List<String> destructiveStatements(String sql) {
  final out = <String>[];
  final noComments = sql
      .split('\n')
      .map((l) {
        final i = l.indexOf('--');
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');
  for (final raw in noComments.split(';')) {
    final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) continue;
    final u = s.toUpperCase();
    if (u.startsWith('CREATE TABLE') || u.contains('SERVERPOD_MIGRATIONS')) {
      continue;
    }
    String? why;
    if (RegExp(r'^DROP TABLE').hasMatch(u)) {
      why = 'drops a table';
    } else if (u.startsWith('TRUNCATE')) {
      why = 'truncates a table';
    } else if (u.startsWith('ALTER TABLE')) {
      if (RegExp(r'\bDROP COLUMN\b').hasMatch(u)) {
        why = 'drops a column';
      } else if (RegExp(r'\bRENAME\b').hasMatch(u)) {
        why = 'renames a table or a column';
      } else if (RegExp(r'\bALTER COLUMN\b.*\bSET NOT NULL\b').hasMatch(u)) {
        why = 'makes a column NOT NULL';
      } else if (RegExp(r'\bALTER COLUMN\b.*\bTYPE\b').hasMatch(u)) {
        why = 'changes a column type';
      } else if (RegExp(r'\bADD COLUMN\b').hasMatch(u) &&
          RegExp(r'\bNOT NULL\b').hasMatch(u) &&
          !RegExp(r'\bDEFAULT\b').hasMatch(u)) {
        why = 'adds a NOT NULL column without a default';
      }
    } else if (RegExp(r'^ALTER TYPE .* RENAME').hasMatch(u)) {
      why = 'renames a type or a value';
    }
    if (why != null) {
      final short = s.length > 120 ? '${s.substring(0, 117)}...' : s;
      out.add('$why ($short)');
    }
  }
  return out;
}

/// Serverpod's destructive warnings in a `migration.json`.
List<String> destructiveWarnings(String migrationJson) {
  final Object? j;
  try {
    j = jsonDecode(migrationJson);
  } on FormatException {
    return const [];
  }
  if (j is! Map) return const [];
  final out = <String>[];
  for (final w in (j['warnings'] as List? ?? const [])) {
    if (w is! Map) continue;
    final type = '${w['type']}';
    final destructive =
        w['destrucive'] == true ||
        w['destructive'] == true ||
        const {'tableDropped', 'columnDropped', 'notNullAdded'}.contains(type);
    if (!destructive) continue;
    out.add('Serverpod: ${w['message'] ?? type}');
  }
  return out;
}

/// The issues of the migrations in [dir] (`<server_package>/migrations` of
/// the new release) whose folder is not in [deployed] (the folders of the
/// running release).
List<MigrationIssue> checkNewMigrations(String dir, Set<String> deployed) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  final issues = <MigrationIssue>[];
  final names =
      d
          .listSync()
          .whereType<Directory>()
          .map((e) => p.basename(e.path))
          .where((n) => !deployed.contains(n))
          .toList()
        ..sort();
  for (final n in names) {
    final sql = File(p.join(dir, n, 'migration.sql'));
    final json = File(p.join(dir, n, 'migration.json'));
    final reasons = <String>{
      if (json.existsSync()) ...destructiveWarnings(json.readAsStringSync()),
      if (sql.existsSync()) ...destructiveStatements(sql.readAsStringSync()),
    };
    for (final r in reasons) {
      issues.add(MigrationIssue(n, r));
    }
  }
  return issues;
}

/// The message of a blue/green deploy that stops on [issues].
String destructiveMessage(List<MigrationIssue> issues) {
  final b = StringBuffer()
    ..writeln(
      'blue/green: the new migrations are not backward compatible; the old '
      'release would run against the new schema during the switch:',
    );
  for (final i in issues.take(20)) {
    b.writeln('  $i');
  }
  if (issues.length > 20) b.writeln('  ... ${issues.length - 20} more');
  b.write(
    'Split the change (expand now, contract in a later release), or deploy '
    'with --allow-destructive-migrations to switch in place (a short '
    'downtime).',
  );
  return b.toString();
}
