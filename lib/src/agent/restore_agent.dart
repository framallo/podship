// `podship agent drill` and `podship agent restore`: run on the server.
//
// drill [STAMP]
//     Restores the dump into a THROWAWAY postgres container (no network, no
//     ports), compares row counts with the counts taken at backup time and
//     with the live database, and deletes the container. Does not touch
//     the live database. Without STAMP it uses the newest backup.
//
// restore --confirmed NAME (STAMP | --dump FILE | --dir DIR) [--volumes]
//     Replaces the live database. podship asks you to type the project
//     name first and passes it as NAME. Steps:
//       1. takes a fresh backup of the current state;
//       2. stops the app services;
//       3. RENAMES the current database to <db>_before_<time> (no drop);
//       4. creates an empty database and restores the dump;
//       5. starts the services again and waits for the health URL.
//     With --volumes, also replaces the configured volumes with the
//     archives of the backup (the old content is kept as a tar.gz next to
//     them). --dir restores a backup folder copied from another server.
//     To undo: stop the services, swap the database names, start them.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'backup_agent.dart';
import 'proc.dart';
import 'settings.dart';

/// Rows per table of the public schema, as `table count` lines.
const _restoredRowsSql = r'''
select format('select %L, count(*) from public.%I', tablename, tablename)
from pg_tables where schemaname = 'public' order by 1 \gexec
''';

/// Which backup to restore.
class RestoreSource {
  RestoreSource({this.stamp, this.dump, this.dir});
  final String? stamp;
  final String? dump;
  final String? dir;
}

class RestoreAgent {
  RestoreAgent(
    this.s, {
    Proc? proc,
    IOSink? out,
    BackupAgent? backup,
    DateTime Function()? clock,
    Future<bool> Function(String url)? healthy,
  }) : proc = proc ?? SystemProc(),
       out = out ?? stdout,
       clock = clock ?? DateTime.now,
       healthy = healthy ?? _httpOk,
       _backup = backup;

  final BackupSettings s;
  final Proc proc;
  final IOSink out;
  final DateTime Function() clock;
  final Future<bool> Function(String url) healthy;
  final BackupAgent? _backup;

  BackupAgent get backupAgent =>
      _backup ?? BackupAgent(s, proc: proc, out: out);

  void log(String m) => out.writeln('[restore] $m');
  Never fail(String m) => throw AgentFailure(m);

  String get _now {
    final t = clock();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// The dump file and the backup folder (null for `--dump`). Checks the
  /// checksums of a folder.
  Future<({String dump, String? dir, String label})> resolve(
    RestoreSource src,
  ) async {
    String dump;
    String? dir = src.dir;
    var label = src.stamp ?? src.dump ?? src.dir ?? '';
    if (dir != null) {
      dump = p.join(dir, s.dumpName);
      log('checking the checksums of $dir');
      if ((await checkSums(dir)).isNotEmpty) {
        fail('SHA-256 checksums do not match');
      }
    } else if (src.dump != null) {
      dump = src.dump!;
    } else {
      var stamp = src.stamp;
      if (stamp == null) {
        final d = Directory(s.plainDir);
        final all = d.existsSync()
            ? (d
                  .listSync()
                  .map((e) => p.basename(e.path))
                  .where(stampPattern.hasMatch)
                  .toList()
                ..sort())
            : <String>[];
        if (all.isEmpty) fail('no backups in ${s.plainDir}');
        stamp = all.last;
      }
      label = stamp;
      dir = p.join(s.plainDir, stamp);
      dump = p.join(dir, s.dumpName);
      if (!File(dump).existsSync()) fail('no $dump');
      log('checking the checksums of $stamp');
      if ((await checkSums(dir)).isNotEmpty) {
        fail('SHA-256 checksums do not match');
      }
    }
    final f = File(dump);
    if (!f.existsSync() || f.lengthSync() == 0) {
      fail('the dump $dump is empty or missing');
    }
    return (dump: dump, dir: dir, label: label);
  }

  Future<String> _dbContainer() => backupAgent.dbContainer();

  Map<String, String> _rows(String text) => {
    for (final l in text.split('\n'))
      if (l.trim().contains(' '))
        l.trim().substring(0, l.trim().indexOf(' ')): l
            .trim()
            .substring(l.trim().indexOf(' ') + 1)
            .trim(),
  };

  /// The restore drill. Returns the number of tables compared.
  Future<int> drill(RestoreSource src) async {
    final (:dump, :dir, :label) = await resolve(src);
    final name = 'podship-drill-${s.project}-$_now';
    try {
      log('throwaway container $name (no network, no ports)');
      final r = await proc.run([
        'docker', 'run', '-d', '--name', name, '--network', 'none', //
        '--memory', '512m', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', s.pgImage,
      ]);
      if (!r.ok) fail('cannot start the throwaway postgres');
      // While it initializes, postgres listens only on the socket; TCP on
      // 127.0.0.1 means it is really up.
      final ready = [
        'docker',
        'exec',
        name,
        'pg_isready',
        '-q',
        '-h',
        '127.0.0.1',
        '-U',
        'postgres',
      ];
      var up = false;
      for (var i = 0; i < 60 && !up; i++) {
        up = (await proc.run(ready)).ok;
        if (!up) await proc.sleep(const Duration(seconds: 1));
      }
      if (!up) fail('the throwaway postgres did not start');
      await proc.run([
        'docker',
        'exec',
        name,
        'psql',
        '-q',
        '-h',
        '127.0.0.1',
        '-U',
        'postgres', //
        '-c', 'create database "${s.dbName}"',
      ]);

      log('pg_restore of $dump');
      final t0 = DateTime.now();
      final rr = await proc.run([
        'docker',
        'exec',
        '-i',
        name,
        'pg_restore',
        '-h',
        '127.0.0.1',
        '-U',
        'postgres', //
        '-d', s.dbName, '--no-owner', '--exit-on-error',
      ], stdinFile: dump);
      if (!rr.ok) fail('pg_restore failed');
      log('restored in ${DateTime.now().difference(t0).inSeconds} s');

      final restored = await proc.run([
        'docker',
        'exec',
        '-i',
        name,
        'psql',
        '-h',
        '127.0.0.1',
        '-U',
        'postgres', //
        '-d', s.dbName, '-Atq', '-F', ' ',
      ], stdinText: _restoredRowsSql);
      final pg = await _dbContainer();
      var live = <String, String>{};
      if (pg.isNotEmpty) {
        final l = await proc.run([
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
          ' ', //
        ], stdinText: _restoredRowsSql);
        live = _rows(l.stdout);
      }
      final countsFile = File(p.join(dir ?? '/nonexistent', s.countsName));
      final atBackup = countsFile.existsSync()
          ? _rows(countsFile.readAsStringSync())
          : <String, String>{};

      var fails = 0, compared = 0;
      String row(String a, String b, String c, String d) =>
          '${a.padRight(52)} ${b.padLeft(10)} ${c.padLeft(10)} ${d.padLeft(10)}';
      out.writeln(row('TABLE', 'RESTORED', 'AT_BACKUP', 'LIVE_NOW'));
      for (final e in _rows(restored.stdout).entries) {
        final t = e.key, n = e.value;
        if (s.drillTables.isNotEmpty && !matchesAny(t, s.drillTables)) continue;
        compared++;
        final at = atBackup[t];
        final now = live[t];
        var mark = '';
        if (at != null && at != n) {
          if (matchesAny(t, s.drillVolatile)) {
            mark = '  (changed during the backup)';
          } else {
            mark = '  <-- DOES NOT MATCH';
            fails++;
          }
        }
        if (mark.isEmpty && now != null && now != n) {
          mark = '  (changed live after the backup)';
        }
        out.writeln('${row(t, n, at ?? '-', now ?? '-')}$mark');
      }
      if (fails > 0) fail('$fails tables do not match the backup counts');
      log('drill OK: $compared tables match backup $label');
      return compared;
    } finally {
      await proc.run(['docker', 'rm', '-f', '-v', name]);
    }
  }

  /// Replaces the live database (and with [volumes], the volumes).
  Future<void> restore(
    RestoreSource src, {
    required String confirmed,
    bool volumes = false,
  }) async {
    final (:dump, :dir, label: _) = await resolve(src);
    if (confirmed != s.projectName) {
      fail('confirmation missing: pass --confirmed ${s.projectName}');
    }
    final compose = s.composeSh;
    if (compose.isEmpty || !File(compose).existsSync()) {
      fail('no current release ($compose)');
    }

    log('1/5 backup of the current state');
    final unit = s.backupUnit;
    if (unit.isNotEmpty &&
        (await proc.run(['sh', '-c', 'command -v systemctl >/dev/null'])).ok &&
        (await proc.run(['systemctl', 'cat', '$unit.service'])).ok) {
      if (!(await proc.run(['systemctl', 'start', '$unit.service'])).ok) {
        fail('the backup of the current state failed; stopping');
      }
    } else {
      try {
        await backupAgent.backup();
      } on AgentFailure catch (e) {
        fail('the backup of the current state failed ($e); stopping');
      }
    }

    var services = s.stopServices;
    if (services.isEmpty) {
      final r = await proc.run([compose, 'config', '--services']);
      if (!r.ok) fail('$compose config --services failed');
      services = [
        for (final l in r.stdout.split('\n'))
          if (l.trim().isNotEmpty && l.trim() != s.dbService) l.trim(),
      ];
    }
    final before = '${s.dbName}_before_$_now';
    log('2/5 stopping ${services.join(' ')}');
    if (!(await proc.run([compose, 'stop', ...services])).ok) {
      fail('cannot stop ${services.join(' ')}');
    }

    final pg = await _dbContainer();
    if (pg.isEmpty) fail('the database container is not running');
    log('3/5 the current database becomes $before');
    final rename = await proc.run([
      'docker', 'exec', '-i', pg, 'psql', '-U', s.dbUser, '-d', 'postgres', //
      '-v', 'ON_ERROR_STOP=1',
      '-c',
      "select pg_terminate_backend(pid) from pg_stat_activity where datname = '${s.dbName}' and pid <> pg_backend_pid();",
      '-c', 'alter database "${s.dbName}" rename to "$before";',
      '-c', 'create database "${s.dbName}";',
    ]);
    if (!rename.ok) fail('cannot rename the database');

    log('4/5 pg_restore');
    final rr = await proc.run([
      'docker',
      'exec',
      '-i',
      pg,
      'pg_restore',
      '-U',
      s.dbUser,
      '-d',
      s.dbName, //
      '--no-owner', '--exit-on-error',
    ], stdinFile: dump);
    if (!rr.ok) {
      fail(
        'pg_restore failed. To go back: rename $before to ${s.dbName} and run: '
        '$compose up -d --force-recreate ${services.join(' ')}',
      );
    }

    if (volumes) {
      if (dir == null) {
        fail('--volumes needs a backup folder (a stamp or --dir)');
      }
      for (final v in s.volumes) {
        String? arc;
        for (final ext in ['tar.zst', 'tar.gz']) {
          final f = p.join(dir, '${v.name}.$ext');
          if (File(f).existsSync()) arc = f;
        }
        if (arc == null) {
          log('no archive for volume ${v.name}; kept');
          continue;
        }
        log('volume ${v.volume} ← ${p.basename(arc)}');
        if (v.isFolder) {
          Directory(v.volume).createSync(recursive: true);
        } else {
          await proc.run(['docker', 'volume', 'create', v.volume]);
        }
        final keep = p.join(p.dirname(dump), '${v.name}-before-$_now.tar.gz');
        await proc.run([
          'docker', 'run', '--rm', '-v', '${v.volume}:/v', s.helperImage, //
          'tar', '-C', '/v', '-czf', '-', '.',
        ], stdoutFile: keep);
        final r = await proc.pipe([
          [arc.endsWith('.zst') ? 'zstd' : 'gzip', '-dc', arc],
          [
            'docker',
            'run',
            '--rm',
            '-i',
            '-v',
            '${v.volume}:/v',
            s.helperImage, //
            'sh', '-c',
            'tar -x -C /v --strip-components=1${v.owner.isEmpty ? '' : ' && chown -R ${v.owner} /v'}',
          ],
        ]);
        if (!r.ok) fail('cannot restore volume ${v.volume}');
      }
    }

    log('5/5 starting ${services.join(' ')}');
    if (!(await proc.run([
      compose,
      'up',
      '-d',
      '--no-build',
      '--force-recreate',
      ...services,
    ])).ok) {
      fail('cannot start ${services.join(' ')}');
    }
    final url = s.healthUrl;
    if (url.isNotEmpty) {
      for (var i = 0; i < 30; i++) {
        if (await healthy(url)) {
          log('done; $url answers. The old database is $before.');
          return;
        }
        await proc.sleep(const Duration(seconds: 4));
      }
      fail('$url does not answer; check the logs');
    }
    log('done. The old database is $before.');
  }
}

Future<bool> _httpOk(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 5));
    final res = await req.close().timeout(const Duration(seconds: 5));
    await res.drain<void>();
    return res.statusCode >= 200 && res.statusCode < 400;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
