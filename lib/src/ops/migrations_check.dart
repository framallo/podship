// The destructive-migration check of a blue/green switch.
//
// During a blue/green switch the old and the new release run against the
// same database: the new one applies its migrations while the old one
// still serves. A migration is safe only when the old code keeps working on
// the new schema (expand/contract).
//
// The check denies by default: every statement must be on a short safe
// list, or the switch stops.
//
// Safe:
// - BEGIN / COMMIT;
// - CREATE TABLE, CREATE SEQUENCE, CREATE TYPE (new objects: the old code
//   does not know them);
// - CREATE INDEX (not UNIQUE) on any table; CREATE UNIQUE INDEX on a table
//   created in the same migration, or with a key column added in the same
//   migration as nullable without a default (the old code leaves it NULL;
//   on other existing columns it can make the old code's inserts fail);
// - ALTER TABLE on a table created in the same migration (any clause);
// - ALTER TABLE on an existing table, when every clause is ADD COLUMN
//   (nullable, or NOT NULL with a DEFAULT) or ALTER COLUMN ... SET DEFAULT;
// - INSERT INTO a table created in the same migration;
// - Serverpod's bookkeeping: the `serverpod_migrations` upsert and its
//   `gen_random_uuid_v7()` function.
//
// Everything else stops the switch, among others: DROP of anything,
// RENAME, ALTER COLUMN TYPE / SET NOT NULL / DROP NOT NULL / DROP DEFAULT,
// ADD CONSTRAINT on an existing table, UPDATE / DELETE / INSERT on an
// existing table (a backfill can change what the old code reads), DO
// blocks and EXECUTE (dynamic SQL is not read), CREATE OR REPLACE of
// other functions, TRUNCATE.
//
// `deploy --allow-destructive-migrations` (also on promote and rollback)
// switches in place instead.
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

/// One SQL statement: [text] with comments removed and whitespace folded;
/// [masked] is the same with the contents of string literals and
/// dollar-quoted bodies replaced by `_`, for keyword matching.
class SqlStatement {
  SqlStatement(this.text, this.masked);
  final String text;
  final String masked;
}

/// Splits [sql] into statements on top-level `;`. Handles `--` and nested
/// `/* */` comments, `'...'` (with `''`), `E'...'` (with backslash
/// escapes), `"..."` identifiers and `$tag$...$tag$` bodies.
List<SqlStatement> splitSql(String sql) {
  final out = <SqlStatement>[];
  final text = StringBuffer();
  final masked = StringBuffer();
  void emit() {
    final t = text.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final m = masked.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) out.add(SqlStatement(t, m));
    text.clear();
    masked.clear();
  }

  void both(String s) {
    text.write(s);
    masked.write(s);
  }

  var i = 0;
  final n = sql.length;
  while (i < n) {
    final c = sql[i];
    final next = i + 1 < n ? sql[i + 1] : '';
    if (c == '-' && next == '-') {
      final e = sql.indexOf('\n', i);
      i = e < 0 ? n : e;
      both(' ');
      continue;
    }
    if (c == '/' && next == '*') {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (sql.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (sql.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      both(' ');
      continue;
    }
    if (c == "'") {
      final escapes =
          i > 0 &&
          (sql[i - 1] == 'E' || sql[i - 1] == 'e') &&
          (i < 2 || !RegExp(r'[A-Za-z0-9_]').hasMatch(sql[i - 2]));
      var j = i + 1;
      while (j < n) {
        if (escapes && sql[j] == r'\') {
          j += 2;
          continue;
        }
        if (sql[j] == "'") {
          if (j + 1 < n && sql[j + 1] == "'") {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      final end = j < n ? j + 1 : n;
      text.write(sql.substring(i, end));
      masked.write("'_'");
      i = end;
      continue;
    }
    if (c == '"') {
      var j = i + 1;
      while (j < n) {
        if (sql[j] == '"') {
          if (j + 1 < n && sql[j + 1] == '"') {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      final end = j < n ? j + 1 : n;
      both(sql.substring(i, end));
      i = end;
      continue;
    }
    if (c == r'$') {
      final m = RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$').matchAsPrefix(sql, i);
      final prevWord = i > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(sql[i - 1]);
      if (m != null && !prevWord) {
        final tag = m.group(0)!;
        final close = sql.indexOf(tag, m.end);
        final end = close < 0 ? n : close + tag.length;
        text.write(sql.substring(i, end));
        // The body stays visible to the matcher as a marker: a DO block or
        // a function body is never read as safe.
        masked.write(r'$_$');
        i = end;
        continue;
      }
    }
    if (c == ';') {
      emit();
      i++;
      continue;
    }
    both(c);
    i++;
  }
  emit();
  return out;
}

// A name, quoted or not, optionally schema-qualified; group 1 is the last
// part.
const _name =
    r'(?:(?:"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*)\.)?("[^"]+"|[A-Za-z_][A-Za-z0-9_$]*)';

String _unquote(String s) =>
    s.startsWith('"') ? s.substring(1, s.length - 1) : s.toLowerCase();

/// Splits [s] on commas outside parentheses.
List<String> _topLevelCommas(String s) {
  final out = <String>[];
  var depth = 0, start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == ',' && depth == 0) {
      out.add(s.substring(start, i).trim());
      start = i + 1;
    }
  }
  out.add(s.substring(start).trim());
  return out;
}

/// Why one ALTER TABLE clause on an existing table is unsafe, or null.
String? _alterClause(String clause) {
  final u = clause.toUpperCase();
  if (RegExp(
    r'^ADD\s+(CONSTRAINT|PRIMARY|UNIQUE|FOREIGN|CHECK|EXCLUDE)\b',
  ).hasMatch(u)) {
    return 'adds a constraint to an existing table';
  }
  if (RegExp(r'^ADD\b').hasMatch(u)) {
    if (RegExp(r'\bNOT\s+NULL\b').hasMatch(u) &&
        !RegExp(r'\bDEFAULT\b').hasMatch(u)) {
      return 'adds a NOT NULL column without a default';
    }
    if (RegExp(r'\b(PRIMARY\s+KEY|UNIQUE|CHECK)\b').hasMatch(u)) {
      return 'adds a column with a constraint to an existing table';
    }
    return null;
  }
  if (RegExp(r'^ALTER\s+(COLUMN\s+)?\S+\s+SET\s+DEFAULT\b').hasMatch(u)) {
    return null;
  }
  if (RegExp(r'^DROP\s+(COLUMN\b|(?!CONSTRAINT)\S)').hasMatch(u)) {
    return 'drops a column';
  }
  if (RegExp(r'^DROP\s+CONSTRAINT\b').hasMatch(u)) {
    return 'drops a constraint';
  }
  if (RegExp(r'^RENAME\b').hasMatch(u)) return 'renames a table or a column';
  if (RegExp(r'\bSET\s+NOT\s+NULL\b').hasMatch(u)) {
    return 'makes a column NOT NULL';
  }
  if (RegExp(r'\bDROP\s+NOT\s+NULL\b').hasMatch(u)) {
    return 'makes a column nullable (the old code may read a NULL)';
  }
  if (RegExp(r'\bDROP\s+DEFAULT\b').hasMatch(u)) {
    return 'drops a column default (the old code may rely on it)';
  }
  if (RegExp(r'\bTYPE\b').hasMatch(u)) return 'changes a column type';
  return 'alters an existing table (not on the safe list)';
}

/// The unsafe statements of [sql], each with its reason. Deny by default:
/// see the top of this file for the safe list.
List<String> destructiveStatements(String sql) {
  final out = <String>[];
  final created = <String>{};
  final addedNullable = <String>{}; // "table.column"

  for (final st in splitSql(sql)) {
    final u = st.masked.toUpperCase();
    final why = _classify(st.masked, u, created, addedNullable);
    if (why != null) {
      final s = st.text;
      final short = s.length > 120 ? '${s.substring(0, 117)}...' : s;
      out.add('$why ($short)');
    }
  }
  return out;
}

String? _classify(
  String m,
  String u,
  Set<String> created,
  Set<String> addedNullable,
) {
  if (RegExp(
    r'^(BEGIN|COMMIT|START TRANSACTION|END)( TRANSACTION| WORK)?$',
  ).hasMatch(u)) {
    return null;
  }
  // Serverpod's bookkeeping.
  if (RegExp(r'^INSERT INTO "?SERVERPOD_MIGRATIONS"? ').hasMatch(u)) {
    return null;
  }
  if (RegExp(
    r'^CREATE OR REPLACE FUNCTION GEN_RANDOM_UUID_V7\(\) RETURNS UUID AS \$_\$ LANGUAGE PLPGSQL VOLATILE$',
  ).hasMatch(u)) {
    return null;
  }
  if (RegExp(r'\$_\$').hasMatch(u) || RegExp(r'^DO\b').hasMatch(u)) {
    return 'runs a DO block or defines a function (its body is not read)';
  }
  if (RegExp(r'\bEXECUTE\b').hasMatch(u)) return 'runs dynamic SQL (EXECUTE)';
  final ct = RegExp(
    '^CREATE (?:UNLOGGED )?TABLE (?:IF NOT EXISTS )?$_name',
    caseSensitive: false,
  ).firstMatch(m);
  if (ct != null) {
    created.add(_unquote(ct.group(1)!));
    return null;
  }
  if (RegExp(r'^CREATE (SEQUENCE|TYPE)\b').hasMatch(u)) return null;
  final ci = RegExp(
    '^CREATE (UNIQUE )?INDEX (?:CONCURRENTLY )?(?:IF NOT EXISTS )?(?:$_name )?ON (?:ONLY )?$_name',
    caseSensitive: false,
  ).firstMatch(m);
  if (ci != null) {
    final table = _unquote(ci.group(3)!);
    if (ci.group(1) == null || created.contains(table)) return null;
    // Safe when a key column is new and nullable without a default: the
    // old code leaves it NULL, and NULLs never collide.
    final cols = RegExp(r'\(([^()]*)\)').firstMatch(m.substring(ci.end));
    final newKey =
        cols != null &&
        !RegExp(r'\bNULLS NOT DISTINCT\b').hasMatch(u) &&
        _topLevelCommas(
          cols.group(1)!,
        ).any((c) => addedNullable.contains('$table.${_unquote(c.trim())}'));
    if (newKey) return null;
    return 'adds a UNIQUE index to an existing table (the old code may insert duplicates)';
  }
  final at = RegExp(
    '^ALTER TABLE (?:IF EXISTS )?(?:ONLY )?$_name (.*)\$',
    caseSensitive: false,
  ).firstMatch(m);
  if (at != null) {
    if (created.contains(_unquote(at.group(1)!))) return null;
    final rest = at.group(2)!;
    if (RegExp(r'^RENAME\b', caseSensitive: false).hasMatch(rest)) {
      return 'renames a table or a column';
    }
    final table = _unquote(at.group(1)!);
    for (final clause in _topLevelCommas(rest)) {
      final why = _alterClause(clause);
      if (why != null) return why;
      final add = RegExp(
        '^ADD (?:COLUMN )?(?:IF NOT EXISTS )?$_name',
        caseSensitive: false,
      ).firstMatch(clause);
      if (add != null &&
          !RegExp(r'\b(NOT NULL|DEFAULT)\b').hasMatch(clause.toUpperCase())) {
        addedNullable.add('$table.${_unquote(add.group(1)!)}');
      }
    }
    return null;
  }
  final ins = RegExp('^INSERT INTO $_name', caseSensitive: false).firstMatch(m);
  if (ins != null) {
    if (created.contains(_unquote(ins.group(1)!))) return null;
    return 'writes rows into an existing table (the old code reads them)';
  }
  if (RegExp(r'^(UPDATE|DELETE|MERGE)\b').hasMatch(u)) {
    return 'changes rows of an existing table (the old code reads them)';
  }
  if (u.startsWith('TRUNCATE')) return 'truncates a table';
  if (RegExp(r'^DROP TABLE\b').hasMatch(u)) return 'drops a table';
  if (RegExp(r'^DROP\b').hasMatch(u)) return 'drops a database object';
  if (RegExp(r'^ALTER TYPE .* RENAME').hasMatch(u)) {
    return 'renames a type or a value';
  }
  final word = u.split(' ').take(3).join(' ');
  return 'not on the safe list ($word)';
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

/// One migration folder: its name, `migration.sql` and `migration.json`
/// (null when missing).
typedef MigrationFiles = ({String name, String? sql, String? json});

/// The issues of [migrations], sorted by name.
List<MigrationIssue> checkMigrations(Iterable<MigrationFiles> migrations) {
  final issues = <MigrationIssue>[];
  final sorted = migrations.toList()..sort((a, b) => a.name.compareTo(b.name));
  for (final m in sorted) {
    final reasons = <String>{
      if (m.json != null) ...destructiveWarnings(m.json!),
      if (m.sql != null) ...destructiveStatements(m.sql!),
    };
    for (final r in reasons) {
      issues.add(MigrationIssue(m.name, r));
    }
  }
  return issues;
}

/// The issues of the migrations in [dir] (`<server_package>/migrations` of
/// the new release) whose folder is not in [deployed] (the folders of the
/// running release).
List<MigrationIssue> checkNewMigrations(String dir, Set<String> deployed) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  String? read(String n, String f) {
    final file = File(p.join(dir, n, f));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  return checkMigrations([
    for (final e in d.listSync().whereType<Directory>())
      if (!deployed.contains(p.basename(e.path)))
        (
          name: p.basename(e.path),
          sql: read(p.basename(e.path), 'migration.sql'),
          json: read(p.basename(e.path), 'migration.json'),
        ),
  ]);
}

/// The marker lines of [remoteMigrationsScript].
const _mBegin = '@@PODSHIP-MIGRATION ';
const _mFile = '@@PODSHIP-FILE ';

/// Shell: prints the `migration.sql` and `migration.json` of every folder
/// of [dir] (`<release>/<server>/migrations` on the server) whose name is
/// not in [skip], between marker lines. [parseRemoteMigrations] reads it.
String remoteMigrationsScript(String dir, Set<String> skip) {
  final q = "'${dir.replaceAll("'", "'\\''")}'";
  final names = skip.map((n) => "'${n.replaceAll("'", "")}'").join(' ');
  return '''
cd $q 2>/dev/null || exit 0
for d in */; do
  d=\${d%/}
  case " $names " in *" '\$d' "*) continue;; esac
  echo "$_mBegin\$d"
  for f in migration.sql migration.json; do
    [ -f "\$d/\$f" ] || continue
    echo "$_mFile\$f"
    cat "\$d/\$f"
    echo
  done
done
''';
}

/// Reads the output of [remoteMigrationsScript].
List<MigrationFiles> parseRemoteMigrations(String out) {
  final res = <MigrationFiles>[];
  String? name, file;
  final files = <String, StringBuffer>{};
  void flush() {
    final n = name;
    if (n != null) {
      res.add((
        name: n,
        sql: files['migration.sql']?.toString(),
        json: files['migration.json']?.toString(),
      ));
    }
    files.clear();
    file = null;
  }

  for (final line in const LineSplitter().convert(out)) {
    if (line.startsWith(_mBegin)) {
      flush();
      name = line.substring(_mBegin.length).trim();
    } else if (line.startsWith(_mFile)) {
      final f = line.substring(_mFile.length).trim();
      file = f;
      files[f] = StringBuffer();
    } else if (file != null) {
      files[file]!.writeln(line);
    }
  }
  flush();
  return res;
}

/// The message of a blue/green switch that stops on [issues].
String destructiveMessage(
  List<MigrationIssue> issues, {
  String command = 'deploy',
}) {
  final b = StringBuffer()
    ..writeln(
      'blue/green: the migrations are not backward compatible; the old '
      'and the new release would run against the same schema during the '
      'switch:',
    );
  for (final i in issues.take(20)) {
    b.writeln('  $i');
  }
  if (issues.length > 20) b.writeln('  ... ${issues.length - 20} more');
  b.write(
    'Split the change (expand now, contract in a later release), or '
    '$command with --allow-destructive-migrations to switch in place (a '
    'short downtime).',
  );
  return b.toString();
}
