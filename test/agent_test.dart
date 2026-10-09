// The server-side agent (`podship agent backup|drill|restore`) with a fake
// process runner: no Docker, no postgres, no age.
@Tags(['unit'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/agent/backup_agent.dart';
import 'package:podship/src/agent/proc.dart';
import 'package:podship/src/agent/restore_agent.dart';
import 'package:podship/src/agent/settings.dart';
import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/scripts.dart';
import 'package:podship/src/server/registry.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Records every command. [answer] gives the result of a command; by
/// default it succeeds with no output. Commands that write files (stdout
/// to a file, `-o FILE`, `tar -x -C DIR`, the SQLite copy) write a small
/// file, so the agent finds what it expects.
class FakeProc implements Proc {
  FakeProc([this.answer]);
  final ProcResult? Function(List<String> cmd, String? stdinText)? answer;
  final calls = <String>[];

  ProcResult _do(List<String> cmd, {String? stdinText, String? stdoutFile}) {
    calls.add(cmd.join(' '));
    final r = answer?.call(cmd, stdinText) ?? ProcResult(0);
    if (r.ok) {
      if (stdoutFile != null) {
        File(
          stdoutFile,
        ).writeAsStringSync(r.stdout.isEmpty ? 'data' : r.stdout);
      }
      final o = cmd.indexOf('-o');
      if ((cmd.first == 'zstd' || cmd.first == 'age') && o >= 0) {
        File(cmd[o + 1]).writeAsStringSync('archive');
      }
      final x = cmd.indexOf('-x');
      if (cmd.first == 'tar' && x >= 0) {
        File(
          p.join(cmd[cmd.indexOf('-C') + 1], 'file.txt'),
        ).writeAsStringSync('f');
      }
      if (cmd.contains('python')) {
        final out = cmd[cmd.indexWhere((a) => a.endsWith(':/out'))]
            .split(':')
            .first;
        File(
          p.join(out, cmd.last.replaceAll('/', '_')),
        ).writeAsStringSync('sqlite');
      }
    }
    return stdoutFile == null ? r : ProcResult(r.code, stderr: r.stderr);
  }

  @override
  Future<ProcResult> run(
    List<String> cmd, {
    String? stdinText,
    String? stdinFile,
    String? stdoutFile,
    Map<String, String>? env,
  }) async => _do(cmd, stdinText: stdinText, stdoutFile: stdoutFile);

  @override
  Future<ProcResult> pipe(
    List<List<String>> cmds, {
    String? stdinFile,
    String? stdoutFile,
  }) async {
    var r = ProcResult(0);
    for (final c in cmds) {
      final x = _do(c, stdoutFile: c == cmds.last ? stdoutFile : null);
      if (r.ok && !x.ok) r = x;
    }
    return r;
  }

  @override
  Future<void> sleep(Duration d) async {}

  int indexOf(String part) => calls.indexWhere((c) => c.contains(part));
}

/// Answers of a healthy server.
ProcResult? server(List<String> cmd, String? stdinText) {
  final c = cmd.join(' ');
  if (cmd.first == 'date') {
    return ProcResult(
      0,
      stdout: cmd[1] == '+%F' ? '2026-10-08\n' : '2026-10-08T0330\n',
    );
  }
  if (c.startsWith('docker ps')) return ProcResult(0, stdout: 'pg123\n');
  if (c.contains('pg_restore --list')) {
    return ProcResult(
      0,
      stdout: '1; 0 0 TABLE DATA public a\n2; 0 0 TABLE DATA public b\n',
    );
  }
  if (c.contains('stat -c')) return ProcResult(0, stdout: '1000:1000\n');
  if (c.contains('psql') && stdinText != null) {
    return ProcResult(0, stdout: 'user 3\nticket 5\njob 9\n');
  }
  return null;
}

BackupSettings settingsFor(Directory dir, {String extra = ''}) =>
    BackupSettings.parse('''
PROJECT=demo-prod
PROJECT_NAME=demo
DEST=${dir.path}/backups
DB_NAME=demo
TZ_LOCAL=America/Mexico_City
KEEP_DAYS=1
KEEP_WEEKS=0
KEEP_MONTHS=0
VOLUMES='worker|demo_worker|q.db||'
RECIPIENTS_FILE=${dir.path}/recipients
SECRET_FILES='${dir.path}/env|env ${dir.path}/missing|passwords.yaml'
COMPOSE_SH=${dir.path}/compose.sh
DRILL_VOLATILE='job*'
$extra''');

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('podship-agent-');
    File(p.join(dir.path, 'recipients')).writeAsStringSync('age1xyz\n');
    File(p.join(dir.path, 'env')).writeAsStringSync('SECRET=1\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('SystemProc: stdin and stdout files, pipelines, exit codes', () async {
    final proc = SystemProc(errors: _Sink());
    final inp = p.join(dir.path, 'in.txt');
    File(inp).writeAsStringSync('hello\nworld\n');
    final out = p.join(dir.path, 'out.txt');
    final r = await proc.pipe(
      [
        ['cat'],
        ['tr', 'a-z', 'A-Z'],
      ],
      stdinFile: inp,
      stdoutFile: out,
    );
    expect(r.ok, isTrue);
    expect(File(out).readAsStringSync(), 'HELLO\nWORLD\n');
    final t = await proc.run(['wc', '-l'], stdinText: 'a\nb\n');
    expect(t.stdout.trim(), '2');
    final f = await proc.pipe([
      ['sh', '-c', 'echo x; exit 3'],
      ['cat'],
    ]);
    expect(f.code, 3);
    final e = await proc.run(['sh', '-c', 'echo oops >&2; exit 1']);
    expect(e.stderr.trim(), 'oops');
  });

  group('settings', () {
    test('read the file podship writes (shell quoting)', () {
      final config = PodshipConfig.parse(sampleConfig);
      final prod = resolveEnv(config, config.env('production'), Registry());
      final s = BackupSettings.parse(backupConf(config, prod));
      expect(s.project, isNotEmpty);
      expect(s.projectName, 'demo');
      expect(s.volumes.single.name, 'worker');
      expect(s.volumes.single.volume, 'demo_worker');
      expect(s.volumes.single.sqlite, ['q.db']);
      expect(s.drillTables, ['user*', 'ticket']);
      expect(s.secretFiles.map((e) => e.$2), ['env', 'passwords.yaml']);
      expect(s.recipientsFile, '/srv/podship/etc/demo-backup.recipients');
      expect(BackupSettings.unquote(r"'it'\''s'"), "it's");
    });

    test('a volume that starts with / is a host folder', () {
      expect(VolumeSpec.parse('data|/srv/data|||1000:1000').isFolder, isTrue);
      expect(VolumeSpec.parse('data|/srv/data|||1000:1000').owner, '1000:1000');
      expect(VolumeSpec.parse('w|demo_worker|q.db||').isFolder, isFalse);
    });
  });

  group('retention', () {
    test('keeps today, yesterday, days, weeks and months', () {
      final keep = keepStamps(
        [
          '2026-10-06T0930',
          '2026-10-05T0930',
          '2026-10-05T1200',
          '2026-09-28T0930',
          '2026-09-01T0930',
          '2026-08-01T0930',
          '2026-03-01T0930',
          '2025-01-01T0930',
          'not-a-stamp',
        ],
        '2026-10-06',
        keepDays: 2,
        keepWeeks: 2,
        keepMonths: 3,
      );
      expect(
        keep,
        containsAll([
          '2026-10-06T0930',
          '2026-10-05T0930',
          '2026-10-05T1200',
          '2026-09-28T0930',
          '2026-08-01T0930',
        ]),
      );
      expect(keep, isNot(contains('2026-03-01T0930')));
      expect(keep, isNot(contains('2025-01-01T0930')));
      expect(keep, isNot(contains('not-a-stamp')));
    });

    test('ISO weeks across the new year', () {
      expect(isoWeek(2026, 12, 31), '2026-W53');
      expect(isoWeek(2027, 1, 3), '2026-W53');
      expect(isoWeek(2027, 1, 4), '2027-W01');
      expect(isoWeek(2024, 12, 30), '2025-W01');
    });

    test('sizes and table patterns', () {
      expect(humanSize(512), '512B');
      expect(humanSize(4096), '4.0K');
      expect(humanSize(12 * 1024 * 1024), '12M');
      expect(matchesAny('user_info', ['user*']), isTrue);
      expect(matchesAny('ticket', ['user*', 'ticket']), isTrue);
      expect(matchesAny('tickets', ['ticket']), isFalse);
    });
  });

  group('backup', () {
    test(
      'dump, volume, checksums, encrypted copy, retention, stamp line',
      () async {
        final s = settingsFor(dir);
        // An old backup that retention deletes.
        Directory(
          p.join(s.plainDir, '2026-01-01T0330'),
        ).createSync(recursive: true);
        final proc = FakeProc(server);
        final out = _Sink();
        final stamp = await BackupAgent(
          s,
          proc: proc,
          out: out,
          lockDir: dir.path,
          volumeTmp: dir.path,
        ).backup();
        expect(stamp, '2026-10-08T0330');
        final pub = p.join(s.plainDir, stamp);
        expect(
          Directory(pub).listSync().map((e) => p.basename(e.path)).toSet(),
          {'db.dump', 'counts.txt', 'worker.tar.zst', 'SHA256SUMS'},
        );
        expect(await checkSums(pub), isEmpty);
        expect(File(p.join(s.encDir, '$stamp.tar.age')).existsSync(), isTrue);
        expect(
          Directory(p.join(s.plainDir, '2026-01-01T0330')).existsSync(),
          isFalse,
        );
        // Only the published backup and the encrypted copy are left.
        expect(
          Directory(s.dest).listSync().map((e) => p.basename(e.path)).toSet(),
          {'daily', 'encrypted'},
        );
        // The order of the work.
        final order = [
          'docker exec pg123 pg_dump -U postgres -Fc demo',
          'pg_restore --list',
          'docker volume inspect demo_worker',
          'stat -c %u:%g /v/q.db',
          'python - q.db',
          '--exclude=./q.db',
          'zstd -q -19',
          'age -R ${dir.path}/recipients',
        ].map(proc.indexOf).toList();
        expect(
          order.every((i) => i >= 0),
          isTrue,
          reason: proc.calls.join('\n'),
        );
        expect(order, List.of(order)..sort());
        expect(out.text, contains('[backup] stamp 2026-10-08T0330'));
        expect(out.text, contains('retention: delete 2026-01-01T0330'));
        expect(
          out.text.trim().split('\n').last,
          'PODSHIP_BACKUP_STAMP=2026-10-08T0330',
        );
        // The secret values never reach the log.
        expect(out.text, isNot(contains('SECRET=1')));

        final list = BackupAgent(s, proc: proc, out: out).list();
        expect(list.single, startsWith('2026-10-08T0330 '));
        expect(list.single.split(' '), hasLength(3));
        expect(list.single, endsWith(' yes'));
      },
    );

    test('files that disappear during the volume copy are skipped; other '
        'tar errors still fail', () async {
      ProcResult? copy(List<String> c, String? i, String err) =>
          c.first == 'docker' && c.contains('-cf') && c.last == '.'
          ? ProcResult(1, stderr: err)
          : server(c, i);
      const gone =
          'tar: ./repos/boceto/mirror/.git/objects/pack/pack-1.pack: No such '
          'file or directory\n'
          'tar: ./repos/boceto/mirror/.git/objects/pack/pack-1.idx: No such '
          'file or directory\n'
          'tar: error exit delayed from previous errors\n';
      final out = _Sink();
      final stamp = await BackupAgent(
        settingsFor(dir),
        proc: FakeProc((c, i) => copy(c, i, gone)),
        out: out,
        lockDir: dir.path,
        volumeTmp: dir.path,
      ).backup();
      expect(stamp, '2026-10-08T0330');
      expect(out.text, contains('2 files disappeared during the copy'));

      final dir2 = Directory.systemTemp.createTempSync('podship-agent-');
      addTearDown(() => dir2.deleteSync(recursive: true));
      File(p.join(dir2.path, 'recipients')).writeAsStringSync('age1xyz\n');
      File(p.join(dir2.path, 'env')).writeAsStringSync('SECRET=1\n');
      await expectLater(
        BackupAgent(
          settingsFor(dir2),
          proc: FakeProc((c, i) => copy(c, i, 'tar: ./a: Permission denied\n')),
          out: _Sink(),
          lockDir: dir2.path,
          volumeTmp: dir2.path,
        ).backup(),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'm',
            contains('cannot copy volume'),
          ),
        ),
      );
    });

    test('vanishedFiles reads GNU, BusyBox and bsdtar messages', () {
      expect(
        vanishedFiles(
          'tar: ./x: No such file or directory\n'
          'tar: Exiting with failure status due to previous errors\n',
        ),
        ['./x'],
      );
      expect(
        vanishedFiles(
          'tar: ./y: File removed before we read it\n'
          'tar: Error exit delayed from previous errors.\n',
        ),
        ['./y'],
      );
      expect(vanishedFiles(''), isNull);
      expect(vanishedFiles('tar: ./z: Permission denied\n'), isNull);
      expect(vanishedFiles('docker: Error response from daemon\n'), isNull);
    });

    test('a dump with too few tables fails and publishes nothing', () async {
      final s = settingsFor(dir, extra: 'MIN_TABLES=3\n');
      final out = _Sink();
      await expectLater(
        BackupAgent(
          s,
          proc: FakeProc(server),
          out: out,
          lockDir: dir.path,
          volumeTmp: dir.path,
        ).backup(),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'message',
            contains('only 2 tables'),
          ),
        ),
      );
      expect(Directory(s.plainDir).listSync(), isEmpty);
      expect(
        Directory(s.dest).listSync().map((e) => p.basename(e.path)),
        isNot(contains(startsWith('.in-progress'))),
      );
    });

    test('no database container: a clear error', () async {
      final s = settingsFor(dir);
      final proc = FakeProc(
        (c, i) =>
            c.first == 'docker' && c[1] == 'ps' ? ProcResult(0) : server(c, i),
      );
      await expectLater(
        BackupAgent(s, proc: proc, out: _Sink(), lockDir: dir.path).backup(),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'm',
            contains('no running container'),
          ),
        ),
      );
      expect(proc.indexOf('pg_dump'), -1);
    });
  });

  group('drill and restore', () {
    late BackupSettings s;
    late String bdir;
    setUp(() async {
      s = settingsFor(dir);
      bdir = p.join(s.plainDir, '2026-10-08T0330');
      Directory(bdir).createSync(recursive: true);
      File(p.join(bdir, 'db.dump')).writeAsStringSync('dump');
      File(
        p.join(bdir, 'counts.txt'),
      ).writeAsStringSync('user 3\nticket 5\njob 8\n');
      await writeSums(bdir, ['db.dump', 'counts.txt']);
    });

    test(
      'drill: compares counts, marks volatile tables, removes the container',
      () async {
        final proc = FakeProc(server);
        final out = _Sink();
        final n = await RestoreAgent(
          s,
          proc: proc,
          out: out,
          clock: () => DateTime(2026, 10, 8, 4),
        ).drill(RestoreSource());
        expect(n, 3);
        expect(out.text, contains('(changed during the backup)'));
        expect(
          out.text,
          contains('drill OK: 3 tables match backup 2026-10-08T0330'),
        );
        expect(
          proc.calls.last,
          'docker rm -f -v podship-drill-demo-prod-20261008040000',
        );
      },
    );

    test('drill: a table that does not match fails', () async {
      File(p.join(bdir, 'counts.txt')).writeAsStringSync('user 4\n');
      await writeSums(bdir, ['db.dump', 'counts.txt']);
      final proc = FakeProc(server);
      await expectLater(
        RestoreAgent(
          s,
          proc: proc,
          out: _Sink(),
        ).drill(RestoreSource(stamp: '2026-10-08T0330')),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'm',
            contains('1 tables do not match'),
          ),
        ),
      );
      expect(proc.calls.last, startsWith('docker rm -f -v podship-drill-'));
    });

    test('a changed file fails the checksum check', () async {
      File(p.join(bdir, 'db.dump')).writeAsStringSync('changed');
      await expectLater(
        RestoreAgent(
          s,
          proc: FakeProc(server),
          out: _Sink(),
        ).drill(RestoreSource()),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'm',
            contains('checksums'),
          ),
        ),
      );
    });

    test('restore without the right confirmation touches nothing', () async {
      final proc = FakeProc(server);
      await expectLater(
        RestoreAgent(
          s,
          proc: proc,
          out: _Sink(),
        ).restore(RestoreSource(), confirmed: 'other'),
        throwsA(
          isA<AgentFailure>().having(
            (e) => e.message,
            'm',
            contains('--confirmed demo'),
          ),
        ),
      );
      expect(proc.calls, isEmpty);
    });

    test('restore: backup, stop, rename, restore, start, health', () async {
      File(s.composeSh).writeAsStringSync('#!/bin/sh\n');
      final proc = FakeProc((c, i) {
        if (c.first == s.composeSh && c.contains('config')) {
          return ProcResult(0, stdout: 'postgres\nserver\nworker\n');
        }
        if (c.first == 'sh') return ProcResult(1); // no systemctl
        return server(c, i);
      });
      final backup = _FakeBackup(s);
      final out = _Sink();
      await RestoreAgent(
        s,
        proc: proc,
        out: out,
        backup: backup,
        clock: () => DateTime(2026, 10, 8, 5),
        healthy: (_) async => true,
      ).restore(RestoreSource(stamp: '2026-10-08T0330'), confirmed: 'demo');
      expect(backup.runs, 1);
      final order = [
        '${s.composeSh} stop server worker',
        'rename to "demo_before_20261008050000"',
        'pg_restore -U postgres -d demo --no-owner --exit-on-error',
        '${s.composeSh} up -d --no-build --force-recreate server worker',
      ].map(proc.indexOf).toList();
      expect(order.every((i) => i >= 0), isTrue, reason: proc.calls.join('\n'));
      expect(order, List.of(order)..sort());
      expect(
        out.text,
        contains('The old database is demo_before_20261008050000'),
      );
    });
  });
}

class _FakeBackup extends BackupAgent {
  _FakeBackup(super.s) : super(proc: FakeProc(server), out: _Sink());
  int runs = 0;
  @override
  Future<String> backup() async {
    runs++;
    return '2026-10-08T0500';
  }
}

/// An IOSink that keeps what is written.
class _Sink implements IOSink {
  final _b = StringBuffer();
  String get text => _b.toString();
  @override
  void writeln([Object? o = '']) => _b.writeln(o);
  @override
  void write(Object? o) => _b.write(o);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
