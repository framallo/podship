import 'package:podship/src/release/release.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseId', () {
    test('formats UTC time and a short sha', () {
      final id = ReleaseId.create(
        DateTime.utc(2026, 10, 6, 9, 5, 7),
        'a0dc2b0ffff',
      );
      expect('$id', '20261006-090507-a0dc2b0');
    });
    test('adds a suffix', () {
      expect(
        '${ReleaseId.create(DateTime.utc(2026), 'abcdef1', suffix: 'dirty')}',
        '20260101-000000-abcdef1-dirty',
      );
    });
    test('parses its own output', () {
      for (final s in [
        '20261006-090507-a0dc2b0',
        '20261006-090507-a0dc2b0-adopted',
        '20261006-090507-nogit-dirty',
      ]) {
        expect('${ReleaseId.tryParse(s)}', s);
      }
      expect(ReleaseId.tryParse('latest'), isNull);
      expect(ReleaseId.tryParse('2026-10-06'), isNull);
    });
    test('sorts by time', () {
      final a = ReleaseId.tryParse('20261006-090507-ffffff0')!;
      final b = ReleaseId.tryParse('20261006-090508-0000000')!;
      expect(a.compareTo(b), lessThan(0));
    });
  });

  group('releasesToPrune', () {
    final ids = [for (var i = 1; i <= 8; i++) '2026100$i-000000-abcdef$i'];
    test('keeps the newest N', () {
      expect(
        releasesToPrune(ids, current: ids.last, keep: 3),
        ids.take(5).toList(),
      );
    });
    test('always keeps the current and the previous release', () {
      final got = releasesToPrune(
        ids,
        current: ids[1],
        previous: ids[0],
        keep: 2,
      );
      expect(got, isNot(contains(ids[0])));
      expect(got, isNot(contains(ids[1])));
      expect(got, containsAll(ids.sublist(2, 6)));
    });
    test('ignores names that are not release ids', () {
      expect(
        releasesToPrune(['tmp', ...ids.take(2)], current: ids[1], keep: 1),
        [ids[0]],
      );
    });
    test('keep below one still keeps one', () {
      expect(releasesToPrune(ids.take(2).toList(), current: null, keep: 0), [
        ids[0],
      ]);
    });
  });

  group('previousRelease', () {
    const a = '20261001-000000-aaaaaaa',
        b = '20261002-000000-bbbbbbb',
        c = '20261003-000000-ccccccc';
    test('is the newest older release', () {
      expect(previousRelease([a, b, c], c), b);
    });
    test('skips failed releases', () {
      expect(previousRelease([a, b, c], c, failed: {b}), a);
    });
    test('is null when there is nothing older', () {
      expect(previousRelease([a], a), isNull);
    });
  });
}
