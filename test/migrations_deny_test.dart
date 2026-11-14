@Tags(['unit'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/ops/migrations_check.dart';
import 'package:test/test.dart';

// The destructive-migration check denies by default (review 2026-11-14).
void main() {
  String? first(String sql) {
    final r = destructiveStatements(sql);
    return r.isEmpty ? null : r.first;
  }

  const cases = <String, String>{
    'DO block': r'DO $$ BEGIN ALTER TABLE "t" DROP COLUMN "c"; END $$;',
    'EXECUTE': r"DO $$ BEGIN EXECUTE 'ALTER TABLE t DROP COLUMN c'; END $$;",
    'block comment first': '/* x */ ALTER TABLE "t" DROP COLUMN "c";',
    'nested block comment':
        '/* a /* b */ c */ ALTER TABLE "t" DROP COLUMN "c";',
    'second ADD without default':
        'ALTER TABLE "t" ADD COLUMN "a" bigint NOT NULL DEFAULT 0, '
        'ADD COLUMN "b" bigint NOT NULL;',
    'DROP INDEX': 'DROP INDEX "t_idx";',
    'DROP VIEW': 'DROP VIEW v;',
    'DROP TYPE': 'DROP TYPE "e";',
    'DROP SCHEMA': 'DROP SCHEMA s CASCADE;',
    'DROP CONSTRAINT': 'ALTER TABLE "t" DROP CONSTRAINT "t_fk";',
    'ADD CONSTRAINT FK':
        'ALTER TABLE ONLY "t" ADD CONSTRAINT "t_fk" FOREIGN KEY("x") '
        'REFERENCES "u"("id");',
    'ADD CONSTRAINT CHECK': 'ALTER TABLE "t" ADD CONSTRAINT "c" CHECK (x > 0);',
    'UNIQUE index on old columns':
        'CREATE UNIQUE INDEX "t_u" ON "t" USING btree ("a");',
    'UNIQUE index NULLS NOT DISTINCT':
        'ALTER TABLE "t" ADD COLUMN "k" text; '
        'CREATE UNIQUE INDEX "t_u" ON "t" ("k") NULLS NOT DISTINCT;',
    'DROP DEFAULT': 'ALTER TABLE "t" ALTER COLUMN "a" DROP DEFAULT;',
    'DROP NOT NULL': 'ALTER TABLE "t" ALTER COLUMN "a" DROP NOT NULL;',
    'DELETE': 'DELETE FROM "event";',
    'UPDATE': 'UPDATE "person" SET "x" = NULL;',
    'INSERT into an existing table':
        'INSERT INTO "setting" ("k") SELECT "id" FROM "company";',
    'RENAME TO': 'ALTER TABLE "t" RENAME TO "u";',
    'lowercase': 'alter table t drop column c;',
    'other function':
        r'CREATE OR REPLACE FUNCTION f() RETURNS int AS $$ SELECT 1 $$ '
        'LANGUAGE sql;',
    'unknown statement': 'GRANT ALL ON "t" TO public;',
  };
  for (final e in cases.entries) {
    test('stops: ${e.key}', () => expect(first(e.value), isNotNull));
  }

  test('words inside strings and comments do not count', () {
    expect(
      destructiveStatements(
        '-- DROP TABLE "x";\n'
        '/* ALTER TABLE "y" DROP COLUMN "z"; */\n'
        'CREATE TABLE "note" ("body" text DEFAULT \'DROP TABLE x; DELETE FROM y\');\n',
      ),
      isEmpty,
    );
  });

  test("Serverpod's gen_random_uuid_v7 boilerplate is safe", () {
    expect(
      destructiveStatements(r'''
BEGIN;
create or replace function gen_random_uuid_v7()
returns uuid
as $$
begin
  -- a comment; with a semicolon
  return encode(set_bit(set_bit(overlay(uuid_send(gen_random_uuid())
    placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
    from 1 for 6), 52, 1), 53, 1), 'hex')::uuid;
end
$$
language plpgsql
volatile;
COMMIT;
'''),
      isEmpty,
    );
  });

  test('a UNIQUE index on a new nullable column is safe', () {
    expect(
      destructiveStatements(
        'ALTER TABLE "support_message" ADD COLUMN "clientKey" text;\n'
        'CREATE UNIQUE INDEX "k" ON "support_message" USING btree '
        '("authorAuthUserId", "clientKey");\n',
      ),
      isEmpty,
    );
    // A default fills it for the old code too: duplicates are possible.
    expect(
      first(
        'ALTER TABLE "m" ADD COLUMN "k" text DEFAULT \'x\';\n'
        'CREATE UNIQUE INDEX "k" ON "m" ("a", "k");\n',
      ),
      startsWith('adds a UNIQUE index'),
    );
  });

  test('the remote listing round-trips', () {
    const out =
        '@@PODSHIP-MIGRATION 20261002\n'
        '@@PODSHIP-FILE migration.sql\n'
        'ALTER TABLE "a" DROP COLUMN "c";\n\n'
        '@@PODSHIP-FILE migration.json\n'
        '{"warnings": []}\n\n'
        '@@PODSHIP-MIGRATION 20261003\n'
        '@@PODSHIP-FILE migration.sql\n'
        'ALTER TABLE "a" ADD COLUMN "d" text;\n\n';
    final m = parseRemoteMigrations(out);
    expect(m.map((x) => x.name), ['20261002', '20261003']);
    expect(m.first.json, contains('warnings'));
    final issues = checkMigrations(m);
    expect(issues.single.migration, '20261002');
    expect(
      destructiveMessage(issues, command: 'rollback'),
      contains('rollback with --allow-destructive-migrations'),
    );
  });

  test('the remote listing script skips the known folders', () {
    final dir = Directory.systemTemp.createTempSync('podship-mig-remote');
    try {
      for (final n in ['20261001', '20261002']) {
        Directory(p.join(dir.path, n)).createSync();
        File(
          p.join(dir.path, n, 'migration.sql'),
        ).writeAsStringSync('DROP TABLE "x$n";\n');
      }
      final r = Process.runSync('bash', [
        '-c',
        remoteMigrationsScript(dir.path, {'20261001'}),
      ]);
      final m = parseRemoteMigrations(r.stdout as String);
      expect(m.single.name, '20261002');
      expect(m.single.sql, contains('DROP TABLE "x20261002"'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  // A real migrations folder (Presente's), when PRESENTE_MIGRATIONS names
  // it: `PRESENTE_MIGRATIONS=../presente/presente_server/migrations`.
  final presente = Directory(
    Platform.environment['PRESENTE_MIGRATIONS'] ?? '/nonexistent',
  );
  test("Presente's migrations: only the unsafe ones stop", () {
    final flagged = <String>{
      for (final i in checkNewMigrations(presente.path, const {})) i.migration,
    };
    expect(flagged, {
      '20261015173556348', // DROP NOT NULL
      '20261015184731058', // INSERT/UPDATE backfill of existing tables
      '20261020150304685', // DO block, DROP TABLE
      '20261027030536540-account-names', // UPDATE, SET NOT NULL
      '20261113220104248', // DROP COLUMN, INSERT/UPDATE backfill
    });
  }, skip: presente.existsSync() ? false : 'no Presente checkout');
}
