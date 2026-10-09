@Tags(['unit'])
library;

import 'package:podship/src/server/registry.dart';
import 'package:test/test.dart';

RegistryEntry entry(
  String key, {
  Map<String, int> ports = const {},
  String? dir,
  List<String> domains = const [],
  String? unit,
  String? schedule,
}) {
  final parts = key.split('/');
  return RegistryEntry(
    project: parts[0],
    env: parts[1],
    dir: dir ?? '/srv/${parts.join('-')}',
    composeProject: parts.join('-'),
    ports: ports,
    domains: domains,
    database: 'per_env:${parts.join('-')}/db',
    backupUnit: unit,
    backupSchedule: schedule,
  );
}

void main() {
  test('allocates free ports and skips used and listening ones', () {
    final r = Registry(portMin: 20000, portMax: 20010)
      ..put(entry('a/production', ports: {'web': 20000}));
    final got = r.allocatePorts(
      'b/staging',
      {'web': 0, 'api': 0},
      listening: {20001},
    );
    expect(got, {'web': 20002, 'api': 20003});
  });

  test('keeps the ports an entry already has', () {
    final r = Registry()..put(entry('a/staging', ports: {'web': 20005}));
    expect(r.allocatePorts('a/staging', {'web': 0}), {'web': 20005});
  });

  test('explicit ports are kept as they are', () {
    expect(Registry().allocatePorts('a/p', {'web': 8087, 'api': 0}), {
      'web': 8087,
      'api': 20000,
    });
  });

  test('fails when the range is full', () {
    final r = Registry(portMin: 1, portMax: 1)
      ..put(entry('a/p', ports: {'x': 1}));
    expect(
      () => r.allocatePorts('b/p', {'y': 0}),
      throwsA(isA<RegistryConflict>()),
    );
  });

  test(
    'refuses entries that share a directory, port, domain or backup unit',
    () {
      final r = Registry()
        ..put(
          entry(
            'a/production',
            ports: {'web': 8087},
            domains: ['a.com'],
            unit: 'a-backup',
          ),
        );
      expect(
        () => r.put(entry('b/production', dir: '/srv/a-production')),
        throwsA(isA<RegistryConflict>()),
      );
      expect(
        () => r.put(entry('b/production', ports: {'w': 8087})),
        throwsA(isA<RegistryConflict>()),
      );
      expect(
        () => r.put(entry('b/production', domains: ['a.com'])),
        throwsA(isA<RegistryConflict>()),
      );
      expect(
        () => r.put(entry('b/production', unit: 'a-backup')),
        throwsA(isA<RegistryConflict>()),
      );
      r.put(entry('a/production', ports: {'web': 8087}));
      expect(r.entries, hasLength(1));
    },
  );

  test('backup slots do not collide', () {
    final r = Registry()
      ..put(entry('a/production', schedule: '*-*-* 03:00:00'))
      ..put(
        entry('b/production', schedule: '*-*-* 03:15:00 America/Mexico_City'),
      );
    expect(r.allocateBackupSchedule('c/production'), '*-*-* 03:30:00');
    expect(r.allocateBackupSchedule('a/production'), '*-*-* 03:00:00');
    expect(
      r.allocateBackupSchedule('d/x', timezone: 'Europe/Madrid'),
      '*-*-* 03:30:00 Europe/Madrid',
    );
  });

  test('renders and parses back', () {
    final r = Registry(portMin: 21000, portMax: 21999)
      ..put(
        entry(
          'a/production',
          ports: {'web': 8087},
          domains: ['a.com'],
          unit: 'u',
          schedule: '*-*-* 03:00:00',
        ),
      );
    final back = Registry.parse(r.render());
    expect(back.portMin, 21000);
    final e = back.entries['a/production']!;
    expect(e.ports, {'web': 8087});
    expect(e.domains, ['a.com']);
    expect(e.backupSchedule, '*-*-* 03:00:00');
    expect(Registry.parse('').entries, isEmpty);
    expect(Registry.parse(Registry().render()).entries, isEmpty);
  });

  group('merge3: deploys of different apps on one server', () {
    test('a change to another app meanwhile merges', () {
      final base = Registry()
        ..put(entry('a/production', ports: {'web': 20000}));
      final mine = Registry.parse(base.render())
        ..put(entry('a/production', ports: {'web': 20000}, unit: 'a-backup'));
      final theirs = Registry.parse(base.render())
        ..put(entry('b/production', ports: {'web': 20001}));
      final out = Registry.merge3(base, mine, theirs);
      expect(out.entries.keys, containsAll(['a/production', 'b/production']));
      expect(out.entries['a/production']!.backupUnit, 'a-backup');
      expect(out.entries['b/production']!.ports, {'web': 20001});
    });

    test('jobs and removals merge too', () {
      final base = Registry()
        ..put(entry('a/production'))
        ..put(entry('c/production'));
      final mine = Registry.parse(base.render())..remove('c/production');
      final theirs = Registry.parse(base.render())
        ..putJob(
          ScheduledJob(
            kind: JobKind.backup,
            project: 'b',
            env: 'production',
            conf: '/x.conf',
          ),
        );
      final out = Registry.merge3(base, mine, theirs);
      expect(out.entries.keys, ['a/production']);
      expect(out.jobs.keys, ['backup:b/production']);
    });

    test('the same entry changed both ways is a conflict', () {
      final base = Registry()
        ..put(entry('a/production', ports: {'web': 20000}));
      final mine = Registry.parse(base.render())
        ..put(entry('a/production', ports: {'web': 20005}));
      final theirs = Registry.parse(base.render())
        ..put(entry('a/production', ports: {'web': 20006}));
      expect(
        () => Registry.merge3(base, mine, theirs),
        throwsA(isA<RegistryConflict>()),
      );
    });

    test('a port taken meanwhile by another app is a conflict', () {
      final base = Registry();
      final mine = Registry()
        ..put(entry('a/production', ports: {'web': 20000}));
      final theirs = Registry()
        ..put(entry('b/production', ports: {'web': 20000}));
      expect(
        () => Registry.merge3(base, mine, theirs),
        throwsA(isA<RegistryConflict>()),
      );
    });

    test('no change of mine keeps their file as it is', () {
      final base = Registry()..put(entry('a/production'));
      final theirs = Registry.parse(base.render())..put(entry('b/production'));
      expect(
        Registry.merge3(base, Registry.parse(base.render()), theirs).render(),
        theirs.render(),
      );
    });
  });
}
