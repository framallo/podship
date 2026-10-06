import 'package:podship/src/integrations/changes.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

void main() {
  final journal = <String>[];

  Change change(
    String key, {
    bool fail = false,
    ChangeKind kind = ChangeKind.create,
  }) => Change(
    kind: kind,
    resource: 'dns_record',
    key: key,
    after: {'summary': 'CNAME $key → t.cfargotunnel.com (proxied)'},
    apply: () async {
      if (fail) throw StateError('API said no');
      journal.add('do $key');
      return Undo('undo $key', () async => journal.add('undo $key'));
    },
  );

  setUp(journal.clear);

  test('applies in order and reports the undo steps newest first', () async {
    final r = await applyChanges(
      ChangeSet('t', [change('a'), change('b')]),
      Log.silent(),
    );
    expect(journal, ['do a', 'do b']);
    expect((r.toJson()['undo'] as List).map((u) => (u as Map)['title']), [
      'undo b',
      'undo a',
    ]);
  });

  test('rolls back the applied changes in reverse when one fails', () async {
    final set = ChangeSet('t', [
      change('a'),
      change('b'),
      change('c', fail: true),
      change('d'),
    ]);
    await expectLater(
      applyChanges(set, Log.silent()),
      throwsA(
        isA<ApplyFailed>()
            .having((e) => e.undone, 'undone', ['undo b', 'undo a'])
            .having((e) => '$e', 'text', contains('API said no')),
      ),
    );
    expect(journal, ['do a', 'do b', 'undo b', 'undo a']);
  });

  test('an undo that fails is reported, and the others still run', () async {
    final bad = Change(
      kind: ChangeKind.create,
      resource: 'access_app',
      key: 'x',
      apply: () async => Undo('undo x', () async => throw StateError('gone')),
    );
    final set = ChangeSet('t', [change('a'), bad, change('c', fail: true)]);
    await expectLater(
      applyChanges(set, Log.silent()),
      throwsA(
        isA<ApplyFailed>().having(
          (e) => e.undoFailures.single,
          'f',
          contains('undo x'),
        ),
      ),
    );
    expect(journal, ['do a', 'undo a']);
  });

  test(
    'unchanged changes are not applied and do not count in the plan id',
    () async {
      final a = ChangeSet('t', [change('a')]);
      final b = ChangeSet('t', [
        change('a'),
        Change.unchanged('dns_record', 'CNAME z', state: 'ok'),
      ]);
      expect(a.id, b.id);
      expect(b.pending, hasLength(1));
      await applyChanges(b, Log.silent());
      expect(journal, ['do a']);
    },
  );

  test('the plan id is stable and changes when the plan does', () {
    expect(
      ChangeSet('t', [change('a')]).id,
      ChangeSet('other title', [change('a')]).id,
    );
    expect(
      ChangeSet('t', [change('a')]).id,
      isNot(ChangeSet('t', [change('b')]).id),
    );
    expect(
      ChangeSet('t', [change('a')]).id,
      isNot(ChangeSet('t', [change('a', kind: ChangeKind.update)]).id),
    );
    expect(ChangeSet('t', [change('a')]).id, hasLength(12));
  });

  test('renders before and after, checks and counts', () {
    final text = ChangeSet(
      'app setup demo/staging',
      [
        change('a'),
        Change(
          kind: ChangeKind.update,
          resource: 'dns_record',
          key: 'CNAME b',
          before: {'summary': 'CNAME b → old.cfargotunnel.com (proxied)'},
          after: {'summary': 'CNAME b → new.cfargotunnel.com (proxied)'},
        ),
        Change(
          kind: ChangeKind.delete,
          resource: 'access_app',
          key: 'c',
          before: {'summary': 'podship app'},
        ),
      ],
      checks: [PlanCheck('TLS a', true, 'covered')],
    ).render();
    expect(text, contains('Plan: app setup demo/staging (plan '));
    expect(
      text,
      contains(
        '~ dns_record         CNAME b\n      before: CNAME b → old.cfargotunnel.com (proxied)\n      after:  CNAME b → new.cfargotunnel.com (proxied)',
      ),
    );
    expect(text, contains('- access_app'));
    expect(text, contains('ok TLS a: covered'));
    expect(
      text,
      contains('1 to create, 1 to update, 1 to delete, 0 unchanged.'),
    );
  });
}
