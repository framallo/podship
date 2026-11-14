@Tags(['unit'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/ops/migrations_check.dart';
import 'package:test/test.dart';

void main() {
  group('SQL', () {
    test('additive statements are safe', () {
      expect(
        destructiveStatements('''
BEGIN;
--
-- ACTION CREATE TABLE
--
CREATE TABLE "ops_event" (
    "id" bigserial PRIMARY KEY,
    "companyId" uuid NOT NULL,
    "at" timestamp without time zone NOT NULL
);
CREATE UNIQUE INDEX "ops_event_seq_idx" ON "ops_event" USING btree ("seq");
ALTER TABLE "company" ADD COLUMN "demoSince" timestamp without time zone;
ALTER TABLE "company" ADD COLUMN "plan" text NOT NULL DEFAULT 'trial'::text;
ALTER TABLE ONLY "ops_event" ADD CONSTRAINT "x_fk_0" FOREIGN KEY("a") REFERENCES "y"("id");
INSERT INTO "ops_event" ("companyId", "at") VALUES (gen_random_uuid(), now());
CREATE INDEX "company_plan_idx" ON "company" USING btree ("plan");
ALTER TABLE "company" ADD COLUMN "key" text, ADD COLUMN "n" bigint NOT NULL DEFAULT 0;
ALTER TABLE "company" ALTER COLUMN "plan" SET DEFAULT 'free';
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('presente', '20261113', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261113', "timestamp" = now();
COMMIT;
'''),
        isEmpty,
      );
    });

    test('drops, renames, type changes and NOT NULL are destructive', () {
      final r = destructiveStatements('''
ALTER TABLE "company_plan" DROP COLUMN "graceEndsAt";
DROP TABLE IF EXISTS "work_group" CASCADE;
ALTER TABLE "person" RENAME COLUMN "name" TO "fullName";
ALTER TABLE "person" ALTER COLUMN "age" TYPE bigint;
ALTER TABLE "person" ALTER COLUMN "email" SET NOT NULL;
ALTER TABLE "person" ADD COLUMN "policyId" uuid NOT NULL;
TRUNCATE "notification";
-- DROP TABLE "only_a_comment";
''');
      expect(r, hasLength(7));
      expect(r[0], startsWith('drops a column'));
      expect(r[1], startsWith('drops a table'));
      expect(r[2], startsWith('renames'));
      expect(r[3], startsWith('changes a column type'));
      expect(r[4], startsWith('makes a column NOT NULL'));
      expect(r[5], startsWith('adds a NOT NULL column without a default'));
      expect(r[6], startsWith('truncates'));
    });
  });

  test("Serverpod's destructive warnings count, unique indexes do not", () {
    final r = destructiveWarnings('''
{"warnings": [
  {"type": "columnDropped", "message": "Column \\"graceEndsAt\\" of table \\"company_plan\\" will be dropped.", "destrucive": true},
  {"type": "uniqueIndexCreated", "message": "Unique index", "destrucive": false},
  {"type": "tableDropped", "message": "Table \\"work_group\\" will be dropped.", "destrucive": true}
]}
''');
    expect(r, [
      'Serverpod: Column "graceEndsAt" of table "company_plan" will be dropped.',
      'Serverpod: Table "work_group" will be dropped.',
    ]);
    expect(destructiveWarnings('not json'), isEmpty);
  });

  test('only migrations the running release does not have are checked', () {
    final dir = Directory.systemTemp.createTempSync('podship-mig');
    try {
      void mig(String name, String sql) {
        Directory(p.join(dir.path, name)).createSync();
        File(p.join(dir.path, name, 'migration.sql')).writeAsStringSync(sql);
      }

      mig('20261001', 'DROP TABLE "old";');
      mig('20261002', 'ALTER TABLE "a" ADD COLUMN "b" text;');
      mig('20261003', 'ALTER TABLE "a" DROP COLUMN "c";');
      File(p.join(dir.path, 'migration_registry.txt')).writeAsStringSync('x');
      final issues = checkNewMigrations(dir.path, {'20261001'});
      expect(issues, hasLength(1));
      expect(issues.single.migration, '20261003');
      expect(
        destructiveMessage(issues),
        contains('--allow-destructive-migrations'),
      );
      expect(checkNewMigrations(dir.path, {'20261001', '20261003'}), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
