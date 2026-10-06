// Release ids and retention.
//
// A release id is `YYYYMMDD-HHMMSS-<sha7>` in UTC, with `-dirty` when the
// files came from a working tree with uncommitted changes, or `-adopted` for
// a setup that existed before podship. Ids sort by time as plain strings.

/// A parsed release id.
class ReleaseId implements Comparable<ReleaseId> {
  ReleaseId(this.time, this.sha, {this.suffix});

  /// Builds the id for a release made at [time] from commit [sha].
  factory ReleaseId.create(DateTime time, String sha, {String? suffix}) {
    final t = time.toUtc();
    return ReleaseId(
      DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second),
      sha.length > 7 ? sha.substring(0, 7) : sha,
      suffix: suffix,
    );
  }

  static final _re = RegExp(
    r'^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-([0-9a-f]{4,40}|nogit)(?:-(dirty|adopted))?$',
  );

  /// Parses [s], or returns null when it is not a release id.
  static ReleaseId? tryParse(String s) {
    final m = _re.firstMatch(s);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    return ReleaseId(
      DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)),
      m.group(7)!,
      suffix: m.group(8),
    );
  }

  final DateTime time;
  final String sha;
  final String? suffix;

  @override
  String toString() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = time;
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-$sha'
        '${suffix == null ? '' : '-$suffix'}';
  }

  @override
  int compareTo(ReleaseId other) => toString().compareTo(other.toString());

  @override
  bool operator ==(Object other) =>
      other is ReleaseId && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// Picks the releases to delete.
///
/// Keeps the newest [keep] releases, and always keeps [current] and
/// [previous] (the rollback target), even when they are older.
List<String> releasesToPrune(
  List<String> releases, {
  required String? current,
  String? previous,
  required int keep,
}) {
  final sorted = [...releases.where((r) => ReleaseId.tryParse(r) != null)]
    ..sort((a, b) => b.compareTo(a));
  final keepSet = {...sorted.take(keep < 1 ? 1 : keep)};
  if (current != null) keepSet.add(current);
  if (previous != null) keepSet.add(previous);
  return [
    for (final r in sorted.reversed)
      if (!keepSet.contains(r)) r,
  ];
}

/// The release that `rollback` without `--to` goes to: the newest release
/// older than [current] that did not fail.
String? previousRelease(
  List<String> releases,
  String? current, {
  Set<String> failed = const {},
}) {
  final sorted = [...releases.where((r) => ReleaseId.tryParse(r) != null)]
    ..sort();
  if (current == null) return sorted.isEmpty ? null : sorted.last;
  final older = sorted.where(
    (r) => r.compareTo(current) < 0 && !failed.contains(r),
  );
  return older.isEmpty ? null : older.last;
}
