// `podship agent backup`: runs on the server that holds the data.
//
// Each run writes:
//
//   <DEST>/<LAYOUT_PLAIN>/<stamp>/
//     <DUMP_NAME>     pg_dump -Fc of the database
//     <volume>.tar.zst or .tar.gz   Docker volumes (SQLite files copied with
//                     SQLite's backup API, never with cp)
//     <COUNTS_NAME>   rows per table at backup time
//     SHA256SUMS
//   <DEST>/<LAYOUT_ENC>/<stamp>.tar.age
//     the same files plus the secret files, encrypted with age to the
//     recipients in RECIPIENTS_FILE (age or SSH public keys)
//
// Retention prunes only after the new backup is complete. The last line is
// `PODSHIP_BACKUP_STAMP=<stamp>`; podship and the scheduler read it.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'proc.dart';
import 'settings.dart';

/// Copies one SQLite file with the backup API and checks the copy. Runs in
/// the helper image (python) with the volume at /v and the output at /out.
const sqliteBackupPy = r'''
import sqlite3, sys
name = sys.argv[1]
src = sqlite3.connect("/v/" + name, timeout=30)
dst = sqlite3.connect("/out/" + name.replace("/", "_"))
src.backup(dst)
ok = dst.execute("pragma integrity_check").fetchone()[0]
dst.close(); src.close()
if ok != "ok":
    sys.exit("integrity_check: " + ok)
''';

/// Rows per table of the public schema, as `table count` lines.
const countRowsSql = r'''
select format('select %L, count(*) from %I.%I', tablename, schemaname, tablename)
from pg_tables where schemaname = 'public' order by tablename \gexec
''';

class BackupAgent {
  BackupAgent(
    this.s, {
    Proc? proc,
    IOSink? out,
    String? lockDir,
    String? volumeTmp,
  }) : proc = proc ?? SystemProc(),
       out = out ?? stdout,
       lockDir = lockDir ?? Directory.systemTemp.path,
       volumeTmp = volumeTmp ?? Directory.systemTemp.path;

  final BackupSettings s;
  final Proc proc;
  final IOSink out;
  final String lockDir;

  /// Where the helper container writes SQLite copies (mode 777).
  final String volumeTmp;

  void log(String m) => out.writeln('[backup] $m');

  Never fail(String m) => throw AgentFailure(m);

  /// The local date in TZ_LOCAL, `YYYY-MM-DD`.
  Future<String> today() => _date('+%F');

  /// A new stamp in TZ_LOCAL, `YYYY-MM-DDTHHMM`.
  Future<String> stampNow() => _date('+%Y-%m-%dT%H%M');

  Future<String> _date(String format) async {
    final r = await proc.run(['date', format], env: {'TZ': s.timezone});
    if (!r.ok) fail('date failed');
    return r.stdout.trim();
  }

  /// Every stamp in the plain and the encrypted folders, oldest first.
  List<String> allStamps() {
    final found = <String>{};
    for (final (dir, suffix) in [(s.plainDir, ''), (s.encDir, '.tar.age')]) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final e in d.listSync()) {
        var n = p.basename(e.path);
        if (suffix.isNotEmpty) {
          if (!n.endsWith(suffix)) continue;
          n = n.substring(0, n.length - suffix.length);
        }
        if (stampPattern.hasMatch(n)) found.add(n);
      }
    }
    return found.toList()..sort();
  }

  /// Deletes the stamps retention does not keep.
  Future<void> prune() async {
    final all = allStamps();
    final keep = keepStamps(
      all,
      await today(),
      keepDays: s.keepDays,
      keepWeeks: s.keepWeeks,
      keepMonths: s.keepMonths,
    );
    for (final st in all) {
      if (keep.contains(st)) continue;
      log('retention: delete $st');
      final dir = Directory(p.join(s.plainDir, st));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final enc = File(p.join(s.encDir, '$st.tar.age'));
      if (enc.existsSync()) enc.deleteSync();
    }
  }

  /// `STAMP SIZE ENCRYPTED` lines.
  List<String> list() => [
    for (final st in allStamps())
      '$st ${Directory(p.join(s.plainDir, st)).existsSync() ? humanSize(diskBytes(p.join(s.plainDir, st))) : '-'} '
          '${File(p.join(s.encDir, '$st.tar.age')).existsSync() ? 'yes' : 'no'}',
  ];

  /// The container of the database service.
  Future<String> dbContainer() async {
    if (s.dbContainer.isNotEmpty) return s.dbContainer;
    final r = await proc.run([
      'docker',
      'ps',
      '-q',
      '--filter',
      'label=com.docker.compose.project=${s.project}',
      '--filter',
      'label=com.docker.compose.service=${s.dbService}',
    ]);
    final lines = r.stdout.trim().split('\n').where((l) => l.isNotEmpty);
    return lines.isEmpty ? '' : lines.first.trim();
  }

  Future<bool> _has(String tool) async =>
      (await proc.run(['sh', '-c', 'command -v $tool >/dev/null'])).ok;

  Future<void> _chmod(
    String mode,
    List<String> paths, {
    bool recursive = false,
  }) async {
    if (paths.isEmpty) return;
    await proc.run(['chmod', if (recursive) '-R', mode, ...paths]);
  }

  /// Takes a backup, encrypts a copy, prunes. Returns the stamp.
  Future<String> backup() async {
    Directory(lockDir).createSync(recursive: true);
    final lockFile = File(p.join(lockDir, 'podship-backup-${s.project}.flock'));
    final lock = lockFile.openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.exclusive);
    } on FileSystemException {
      lock.closeSync();
      fail('another backup of ${s.project} is running');
    }
    String? tmp;
    String? vtmp;
    try {
      final recipients = s.recipientsFile;
      if (recipients.isNotEmpty) {
        final f = File(recipients);
        if (!f.existsSync() || f.lengthSync() == 0) {
          fail('the recipients file $recipients is missing or empty');
        }
        if (!await _has('age')) fail('age is not installed (apt install age)');
      }
      final String ext;
      switch (s.compress) {
        case 'zstd':
          if (!await _has('zstd')) fail('zstd is not installed');
          ext = 'tar.zst';
        case 'gzip':
          ext = 'tar.gz';
        default:
          fail('COMPRESS must be zstd or gzip');
      }

      final pg = await dbContainer();
      if (pg.isEmpty) {
        fail(
          'no running container for service ${s.dbService} of project ${s.project}',
        );
      }

      for (final d in [s.dest, s.plainDir, s.encDir]) {
        Directory(d).createSync(recursive: true);
      }
      await _chmod('700', [s.dest, s.plainDir, s.encDir]);

      // One backup per minute: if this minute is taken (a restore right
      // after a backup), wait for the next one.
      var stamp = '';
      var outDir = '';
      bool taken() =>
          FileSystemEntity.typeSync(outDir) != FileSystemEntityType.notFound ||
          File(p.join(s.encDir, '$stamp.tar.age')).existsSync();
      for (var i = 0; i < 15; i++) {
        stamp = await stampNow();
        outDir = p.join(s.plainDir, stamp);
        if (!taken()) break;
        await proc.sleep(const Duration(seconds: 5));
      }
      if (taken()) fail('$outDir already exists');
      tmp = Directory(s.dest).createTempSync('.in-progress-$stamp.').path;
      await _chmod('700', [tmp]);

      log('stamp $stamp');

      // 1. Database. pg_dump runs inside the container and takes a
      //    consistent snapshot without blocking anyone.
      log('pg_dump of ${s.dbName}');
      final dump = p.join(tmp, s.dumpName);
      final d = await proc.run([
        'docker', 'exec', pg, 'pg_dump', '-U', s.dbUser, '-Fc', s.dbName, //
      ], stdoutFile: dump);
      if (!d.ok) fail('pg_dump failed (exit code ${d.code})');
      if (!File(dump).existsSync() || File(dump).lengthSync() == 0) {
        fail('the dump is empty');
      }
      final l = await proc.run([
        'docker', 'exec', '-i', pg, 'pg_restore', '--list', //
      ], stdinFile: dump);
      if (!l.ok) fail('pg_restore cannot read the dump');
      final tables = l.stdout
          .split('\n')
          .where((x) => x.contains(' TABLE DATA '))
          .length;
      if (tables < s.minTables) {
        fail('the dump has only $tables tables with data');
      }
      log(
        'dump: ${humanSize(File(dump).lengthSync())}, $tables tables with data',
      );

      final c = await proc.run(
        [
          'docker',
          'exec',
          '-i',
          pg,
          'psql',
          '-U',
          s.dbUser,
          '-d',
          s.dbName,
          '-Atq',
          '-F',
          ' ',
        ],
        stdinText: countRowsSql,
        stdoutFile: p.join(tmp, s.countsName),
      );
      if (!c.ok) fail('cannot count rows');

      // 2. Volumes.
      final files = [s.dumpName, s.countsName];
      for (final v in s.volumes) {
        log('volume ${v.volume} → ${v.name}.$ext');
        if (v.isFolder) {
          if (!Directory(v.volume).existsSync()) fail('no folder ${v.volume}');
        } else if (!(await proc.run([
          'docker',
          'volume',
          'inspect',
          v.volume,
        ])).ok) {
          fail('no Docker volume ${v.volume}');
        }
        vtmp = Directory(
          volumeTmp,
        ).createTempSync('podship-volume-${v.name}.').path;
        await _chmod('777', [vtmp]);
        final into = p.join(tmp, v.name);
        Directory(into).createSync();
        // SQLite files: copy with the backup API, as the file owner, so the
        // daemon never finds -wal/-shm files it cannot open.
        for (final db in v.sqlite) {
          final st = await proc.run([
            'docker',
            'run',
            '--rm',
            '-v',
            '${v.volume}:/v:ro',
            s.helperImage, //
            'stat', '-c', '%u:%g', '/v/$db',
          ]);
          if (!st.ok) {
            log('volume ${v.volume} has no $db yet; skipped');
            continue;
          }
          final r = await proc.run([
            'docker', 'run', '--rm', '-i', '--network', 'none', //
            '--user',
            st.stdout.trim(),
            '-v',
            '${v.volume}:/v',
            '-v',
            '$vtmp:/out',
            s.helperImage, 'python', '-', db,
          ], stdinText: sqliteBackupPy);
          if (!r.ok) fail('the SQLite copy of $db failed');
          final copy = db.replaceAll('/', '_');
          moveFile(p.join(vtmp, copy), p.join(into, copy));
        }
        // Other files: the listed ones, or the whole volume minus SQLite.
        if (v.files.isNotEmpty) {
          for (final f in v.files) {
            await proc.pipe([
              [
                'docker',
                'run',
                '--rm',
                '-v',
                '${v.volume}:/v:ro',
                s.helperImage, //
                'sh', '-c', 'test -e /v/$f && tar -C /v -cf - ./$f || true',
              ],
              ['tar', '-x', '-C', into],
            ]);
          }
        } else {
          final r = await proc.pipe([
            [
              'docker',
              'run',
              '--rm',
              '-v',
              '${v.volume}:/v:ro',
              s.helperImage, //
              'tar', '-C', '/v',
              for (final db in v.sqlite) ...[
                '--exclude=./$db',
                '--exclude=./$db-wal',
                '--exclude=./$db-shm',
              ],
              '-cf', '-', '.',
            ],
            ['tar', '-x', '-C', into],
          ]);
          if (!r.ok) fail('cannot copy volume ${v.volume}');
        }
        final arc = p.join(tmp, '${v.name}.$ext');
        final r = s.compress == 'zstd'
            ? await proc.pipe([
                ['tar', '-C', tmp, '-cf', '-', v.name],
                ['zstd', '-q', '-19', '-o', arc],
              ])
            : await proc.run(['tar', '-C', tmp, '-czf', arc, v.name]);
        if (!r.ok) fail('cannot compress volume ${v.volume}');
        Directory(into).deleteSync(recursive: true);
        Directory(vtmp).deleteSync(recursive: true);
        vtmp = null;
        files.add('${v.name}.$ext');
      }

      await writeSums(tmp, files);
      files.add('SHA256SUMS');

      // 3. Encrypted package: the same files plus the secret files. The
      //    plain copy of the secrets lives only in the 0700 temp folder; it
      //    is never printed.
      if (recipients.isNotEmpty) {
        log('encrypting the off-site copy');
        final pkg = p.join(tmp, 'package', stamp);
        Directory(p.join(pkg, s.secretsName)).createSync(recursive: true);
        for (final f in files) {
          File(p.join(tmp, f)).copySync(p.join(pkg, f));
        }
        for (final (src, name) in s.secretFiles) {
          if (File(src).existsSync()) {
            File(src).copySync(p.join(pkg, s.secretsName, name));
          }
        }
        final enc = p.join(tmp, '$stamp.tar.age');
        final r = await proc.pipe([
          ['tar', '-C', p.join(tmp, 'package'), '-cf', '-', stamp],
          ['age', '-R', recipients, '-o', enc],
        ]);
        if (!r.ok || !File(enc).existsSync() || File(enc).lengthSync() == 0) {
          fail('the encrypted package is empty');
        }
        Directory(p.join(tmp, 'package')).deleteSync(recursive: true);
        await _chmod('600', [enc]);
        moveFile(enc, p.join(s.encDir, '$stamp.tar.age'));
      } else {
        log('no recipients: no encrypted copy');
      }

      // 4. Publish only when everything above worked.
      Directory(outDir).createSync();
      for (final f in files) {
        moveFile(p.join(tmp, f), p.join(outDir, f));
      }
      await _chmod('go-rwx', [outDir], recursive: true);
      log('done: $outDir (${humanSize(diskBytes(outDir))})');

      // 5. Retention.
      await prune();
      final count = Directory(s.plainDir).listSync().length;
      log('on disk: $count backups, ${humanSize(diskBytes(s.dest))}');
      out.writeln('PODSHIP_BACKUP_STAMP=$stamp');
      return stamp;
    } finally {
      for (final d in [tmp, vtmp]) {
        if (d != null && Directory(d).existsSync()) {
          Directory(d).deleteSync(recursive: true);
        }
      }
      try {
        lock.unlockSync();
      } catch (_) {}
      lock.closeSync();
    }
  }
}
