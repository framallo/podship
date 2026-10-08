// The backup settings file (`<home>/etc/<unit>.conf`) and the parts of a
// backup that need no processes: retention, checksums, sizes.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A backup or restore failed. The message is safe to print.
class AgentFailure implements Exception {
  AgentFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The settings podship writes for an environment: `KEY=value` lines, the
/// value bare or in single quotes (`'it'\''s'`). No secrets.
class BackupSettings {
  BackupSettings(this.values);

  factory BackupSettings.parse(String text) {
    final values = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      values[line.substring(0, eq)] = unquote(line.substring(eq + 1));
    }
    return BackupSettings(values);
  }

  factory BackupSettings.load(String path) {
    final f = File(path);
    if (!f.existsSync()) throw AgentFailure('no settings file $path');
    final s = BackupSettings.parse(f.readAsStringSync());
    for (final k in ['PROJECT', 'DEST', 'DB_NAME']) {
      if (s.get(k).isEmpty) throw AgentFailure('$k is not set in $path');
    }
    return s;
  }

  /// Undoes the shell quoting of `shq`: bare words and `'...'` parts.
  static String unquote(String v) {
    final b = StringBuffer();
    var i = 0;
    while (i < v.length) {
      final c = v[i];
      if (c == "'") {
        final end = v.indexOf("'", i + 1);
        if (end < 0) {
          b.write(v.substring(i + 1));
          break;
        }
        b.write(v.substring(i + 1, end));
        i = end + 1;
      } else if (c == r'\' && i + 1 < v.length) {
        b.write(v[i + 1]);
        i += 2;
      } else if (c == '"') {
        final end = v.indexOf('"', i + 1);
        b.write(v.substring(i + 1, end < 0 ? v.length : end));
        i = end < 0 ? v.length : end + 1;
      } else {
        b.write(c);
        i++;
      }
    }
    return b.toString();
  }

  final Map<String, String> values;

  String get(String key, [String fallback = '']) {
    final v = values[key];
    return v == null || v.isEmpty ? fallback : v;
  }

  int getInt(String key, int fallback) => int.tryParse(get(key)) ?? fallback;

  /// Space-separated words.
  List<String> words(String key) =>
      get(key).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  String get project => get('PROJECT');
  String get projectName => get('PROJECT_NAME');
  String get dest => get('DEST');
  String get dbName => get('DB_NAME');
  String get layoutPlain => get('LAYOUT_PLAIN', 'daily');
  String get layoutEnc => get('LAYOUT_ENC', 'encrypted');
  String get dumpName => get('DUMP_NAME', 'db.dump');
  String get countsName => get('COUNTS_NAME', 'counts.txt');
  String get secretsName => get('SECRETS_NAME', 'secrets');
  String get dbService => get('DB_SERVICE', 'postgres');
  String get dbUser => get('DB_USER', 'postgres');
  String get dbContainer => get('DB_CONTAINER');
  String get timezone => get('TZ_LOCAL', 'UTC');
  int get keepDays => getInt('KEEP_DAYS', 14);
  int get keepWeeks => getInt('KEEP_WEEKS', 8);
  int get keepMonths => getInt('KEEP_MONTHS', 6);
  String get compress => get('COMPRESS', 'zstd');
  String get helperImage => get('HELPER_IMAGE', 'python:3.12-alpine');
  String get pgImage => get('PG_IMAGE', 'postgres:16-alpine');
  String get recipientsFile => get('RECIPIENTS_FILE');
  int get minTables => getInt('MIN_TABLES', 1);
  List<VolumeSpec> get volumes => [
    for (final w in words('VOLUMES')) VolumeSpec.parse(w),
  ];

  /// `source|name` pairs: files copied into the encrypted package only.
  List<(String, String)> get secretFiles => [
    for (final w in words('SECRET_FILES'))
      if (w.contains('|'))
        (w.substring(0, w.indexOf('|')), w.substring(w.indexOf('|') + 1)),
  ];
  List<String> get drillTables => words('DRILL_TABLES');
  List<String> get drillVolatile => words('DRILL_VOLATILE');
  List<String> get stopServices => words('STOP_SERVICES');
  String get composeSh => get('COMPOSE_SH');
  String get healthUrl => get('HEALTH_URL');
  String get backupUnit => get('BACKUP_UNIT');

  String get plainDir => p.join(dest, layoutPlain);
  String get encDir => p.join(dest, layoutEnc);
}

/// One volume entry: `name|volume|sqlite files|files|owner`. The volume is
/// a Docker volume name or an absolute host folder.
class VolumeSpec {
  VolumeSpec(this.name, this.volume, this.sqlite, this.files, this.owner);

  factory VolumeSpec.parse(String s) {
    final f = s.split('|');
    String at(int i) => i < f.length ? f[i] : '';
    List<String> list(int i) =>
        at(i).split(',').where((x) => x.isNotEmpty).toList();
    return VolumeSpec(at(0), at(1), list(2), list(3), at(4));
  }

  final String name;
  final String volume;
  final List<String> sqlite;
  final List<String> files;
  final String owner;

  /// A host folder (a bind mount), not a Docker volume.
  bool get isFolder => volume.startsWith('/');
}

/// A backup stamp: `2026-10-07T0330`.
final stampPattern = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{4}$');

int _days(int y, int m, int d) =>
    DateTime.utc(y, m, d).difference(DateTime.utc(1970)).inDays;

/// The ISO 8601 week of a date, like `2026-W41`.
String isoWeek(int y, int m, int d) {
  final date = DateTime.utc(y, m, d);
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final ty = thursday.year;
  final week = (thursday.difference(DateTime.utc(ty)).inDays ~/ 7) + 1;
  return '$ty-W${week.toString().padLeft(2, '0')}';
}

/// The stamps retention keeps: everything from [today] (`YYYY-MM-DD`) and
/// yesterday, plus the newest stamp of each of the last [keepDays] days,
/// [keepWeeks] ISO weeks and [keepMonths] months.
Set<String> keepStamps(
  Iterable<String> stamps,
  String today, {
  required int keepDays,
  required int keepWeeks,
  required int keepMonths,
}) {
  final t = today.split('-').map(int.parse).toList();
  final recent = _days(t[0], t[1], t[2]) - 1;
  final sorted = stamps.where(stampPattern.hasMatch).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  final keep = <String>{};
  final days = <String>{}, weeks = <String>{}, months = <String>{};
  for (final s in sorted) {
    final d = s.substring(0, 10);
    final y = int.parse(d.substring(0, 4));
    final m = int.parse(d.substring(5, 7));
    final dd = int.parse(d.substring(8, 10));
    if (_days(y, m, dd) >= recent) keep.add(s);
    final w = isoWeek(y, m, dd);
    final mo = d.substring(0, 7);
    if (!days.contains(d) && days.length < keepDays) {
      days.add(d);
      keep.add(s);
    }
    if (!weeks.contains(w) && weeks.length < keepWeeks) {
      weeks.add(w);
      keep.add(s);
    }
    if (!months.contains(mo) && months.length < keepMonths) {
      months.add(mo);
      keep.add(s);
    }
  }
  return keep;
}

/// The SHA-256 of a file, streamed.
Future<String> sha256File(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// Writes `SHA256SUMS` in [dir] for [names], in the `sha256sum` format.
Future<void> writeSums(String dir, List<String> names) async {
  final b = StringBuffer();
  for (final n in names) {
    b.writeln('${await sha256File(p.join(dir, n))}  $n');
  }
  File(p.join(dir, 'SHA256SUMS')).writeAsStringSync(b.toString());
}

/// Checks `SHA256SUMS` in [dir]. Returns the names that do not match.
Future<List<String>> checkSums(String dir) async {
  final f = File(p.join(dir, 'SHA256SUMS'));
  if (!f.existsSync()) return ['SHA256SUMS'];
  final bad = <String>[];
  for (final line in f.readAsLinesSync()) {
    final m = RegExp(r'^([0-9a-f]{64}) [ *](.+)$').firstMatch(line.trim());
    if (m == null) continue;
    final file = File(p.join(dir, m[2]!));
    if (!file.existsSync() || await sha256File(file.path) != m[1]) {
      bad.add(m[2]!);
    }
  }
  return bad;
}

/// The bytes under [path] (a file or a folder).
int diskBytes(String path) {
  final t = FileSystemEntity.typeSync(path, followLinks: false);
  if (t == FileSystemEntityType.file) return File(path).lengthSync();
  if (t != FileSystemEntityType.directory) return 0;
  var n = 0;
  for (final e in Directory(
    path,
  ).listSync(recursive: true, followLinks: false)) {
    if (e is File) n += e.lengthSync();
  }
  return n;
}

/// A size like `du -h`: `512B`, `4.0K`, `12M`, `1.2G`.
String humanSize(int bytes) {
  const units = ['B', 'K', 'M', 'G', 'T'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  if (i == 0) return '${bytes}B';
  return v < 10
      ? '${v.toStringAsFixed(1)}${units[i]}'
      : '${v.round()}${units[i]}';
}

/// Whether table [t] matches one of the shell patterns (`user*`, `job?`).
bool matchesAny(String t, List<String> patterns) {
  for (final pat in patterns) {
    final re = StringBuffer('^');
    for (final ch in pat.split('')) {
      re.write(switch (ch) {
        '*' => '.*',
        '?' => '.',
        _ => RegExp.escape(ch),
      });
    }
    re.write(r'$');
    if (RegExp(re.toString()).hasMatch(t)) return true;
  }
  return false;
}

/// Moves a file, also across file systems (like `mv`).
void moveFile(String from, String to) {
  try {
    File(from).renameSync(to);
  } on FileSystemException {
    File(from).copySync(to);
    File(from).deleteSync();
  }
}
