// The server registry: one file per server that lists every project and
// environment podship runs there.
//
// It lives at /srv/podship/registry.yaml. podship reads it before it changes
// anything, so two projects never take the same directory, compose project,
// port, domain, database or backup slot.

import 'dart:convert';

import 'package:yaml/yaml.dart';

/// A conflict with another registry entry.
class RegistryConflict implements Exception {
  RegistryConflict(this.message);
  final String message;
  @override
  String toString() => 'registry: $message';
}

/// One project environment on the server.
class RegistryEntry {
  RegistryEntry({
    required this.project,
    required this.env,
    required this.dir,
    required this.composeProject,
    this.ports = const {},
    this.domains = const [],
    this.database = '',
    this.backupUnit,
    this.backupSchedule,
    this.updated = '',
  });

  factory RegistryEntry.fromMap(Map m) => RegistryEntry(
    project: '${m['project']}',
    env: '${m['env']}',
    dir: '${m['dir']}',
    composeProject: '${m['compose_project']}',
    ports: {
      for (final e in ((m['ports'] as Map?) ?? const {}).entries)
        '${e.key}': e.value as int,
    },
    domains: [for (final d in (m['domains'] as List?) ?? const []) '$d'],
    database: '${m['database'] ?? ''}',
    backupUnit: m['backup_unit'] as String?,
    backupSchedule: m['backup_schedule'] as String?,
    updated: '${m['updated'] ?? ''}',
  );

  final String project;
  final String env;
  final String dir;
  final String composeProject;
  final Map<String, int> ports;
  final List<String> domains;

  /// `per_env:<db>` or `shared:<db>`.
  final String database;
  final String? backupUnit;
  final String? backupSchedule;
  final String updated;

  String get key => '$project/$env';

  Map<String, Object?> toMap() => {
    'project': project,
    'env': env,
    'dir': dir,
    'compose_project': composeProject,
    'ports': ports,
    'domains': domains,
    'database': database,
    'backup_unit': ?backupUnit,
    'backup_schedule': ?backupSchedule,
    'updated': updated,
  };

  RegistryEntry copyWith({
    Map<String, int>? ports,
    String? backupSchedule,
    String? updated,
  }) => RegistryEntry(
    project: project,
    env: env,
    dir: dir,
    composeProject: composeProject,
    ports: ports ?? this.ports,
    domains: domains,
    database: database,
    backupUnit: backupUnit,
    backupSchedule: backupSchedule ?? this.backupSchedule,
    updated: updated ?? this.updated,
  );
}

class Registry {
  Registry({
    Map<String, RegistryEntry>? entries,
    this.portMin = 20000,
    this.portMax = 20999,
  }) : entries = entries ?? {};

  /// Parses the registry text. Empty text is an empty registry.
  factory Registry.parse(String text) {
    if (text.trim().isEmpty) return Registry();
    final doc = loadYaml(text);
    if (doc is! YamlMap) throw RegistryConflict('the file is not a map');
    final range = doc['port_range'];
    final entries = <String, RegistryEntry>{};
    final m = doc['entries'];
    if (m is YamlMap) {
      for (final e in m.entries) {
        entries['${e.key}'] = RegistryEntry.fromMap(e.value as Map);
      }
    }
    return Registry(
      entries: entries,
      portMin: range is YamlList ? range[0] as int : 20000,
      portMax: range is YamlList ? range[1] as int : 20999,
    );
  }

  final Map<String, RegistryEntry> entries;
  final int portMin;
  final int portMax;

  /// Ports in use by entries other than [exceptKey].
  Set<int> usedPorts({String? exceptKey}) => {
    for (final e in entries.values)
      if (e.key != exceptKey) ...e.ports.values,
  };

  /// Checks that [entry] does not collide with another entry. Throws
  /// [RegistryConflict].
  void check(RegistryEntry entry) {
    for (final o in entries.values) {
      if (o.key == entry.key) continue;
      void clash(String what) =>
          throw RegistryConflict('${entry.key} and ${o.key} would share $what');
      if (o.dir == entry.dir) clash('the directory ${o.dir}');
      if (o.composeProject == entry.composeProject) {
        clash('the compose project ${o.composeProject}');
      }
      final p = o.ports.values.toSet().intersection(entry.ports.values.toSet());
      if (p.isNotEmpty) clash('port ${p.first}');
      final d = o.domains.toSet().intersection(entry.domains.toSet());
      if (d.isNotEmpty) clash('the domain ${d.first}');
      if (entry.database.startsWith('shared:') &&
          o.database == entry.database) {
        clash('the database ${entry.database}');
      }
      if (entry.backupUnit != null && o.backupUnit == entry.backupUnit) {
        clash('the backup unit ${o.backupUnit}');
      }
    }
  }

  /// Gives a port to every name whose value is 0. [listening] are ports
  /// that something else on the server already uses.
  Map<String, int> allocatePorts(
    String key,
    Map<String, int> wanted, {
    Set<int> listening = const {},
  }) {
    final existing = entries[key]?.ports ?? const {};
    final used = {...usedPorts(exceptKey: key), ...listening};
    final out = <String, int>{};
    for (final e in wanted.entries) {
      if (e.value > 0) {
        out[e.key] = e.value;
        used.add(e.value);
      }
    }
    for (final e in wanted.entries) {
      if (e.value > 0) continue;
      // Keep the port this entry already had.
      final had = existing[e.key];
      if (had != null && !used.contains(had)) {
        out[e.key] = had;
        used.add(had);
        continue;
      }
      var port = portMin;
      while (used.contains(port)) {
        port++;
        if (port > portMax) {
          throw RegistryConflict('no free port in $portMin-$portMax');
        }
      }
      out[e.key] = port;
      used.add(port);
    }
    return out;
  }

  /// A daily backup time that no other entry uses: 03:00, 03:15, 03:30 …
  /// in the given time zone. Keeps the entry's current slot.
  String allocateBackupSchedule(String key, {String timezone = 'UTC'}) {
    final had = entries[key]?.backupSchedule;
    if (had != null) return had;
    final used = {
      for (final e in entries.values)
        if (e.key != key && e.backupSchedule != null) _slot(e.backupSchedule!),
    };
    for (var i = 0; i < 96; i++) {
      final minutes = 3 * 60 + i * 15;
      final h = (minutes ~/ 60) % 24, m = minutes % 60;
      final slot = '${_two(h)}:${_two(m)}';
      if (!used.contains(slot)) {
        return '*-*-* $slot:00${timezone == 'UTC' ? '' : ' $timezone'}';
      }
    }
    throw RegistryConflict('no free backup slot');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _slot(String onCalendar) {
    final m = RegExp(r'(\d{2}):(\d{2})').firstMatch(onCalendar);
    return m == null ? onCalendar : '${m[1]}:${m[2]}';
  }

  /// Adds or replaces [entry] after [check].
  void put(RegistryEntry entry) {
    check(entry);
    entries[entry.key] = entry;
  }

  RegistryEntry? remove(String key) => entries.remove(key);

  /// The registry as YAML. JSON values are valid YAML; one entry per block.
  String render() {
    final b = StringBuffer()
      ..writeln('# podship server registry. podship keeps it up to date.')
      ..writeln('# Every project environment on this server, with its')
      ..writeln('# directory, ports, domains, database and backup slot.')
      ..writeln('version: 1')
      ..writeln('port_range: [$portMin, $portMax]')
      ..writeln('entries:');
    final keys = entries.keys.toList()..sort();
    if (keys.isEmpty) b.writeln('  {}');
    for (final k in keys) {
      b.writeln('  ${jsonEncode(k)}:');
      entries[k]!.toMap().forEach((field, value) {
        b.writeln('    $field: ${jsonEncode(value)}');
      });
    }
    return b.toString();
  }
}
