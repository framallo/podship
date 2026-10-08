// The server registry: one file per server that lists every project and
// environment podship runs there.
//
// It lives at /srv/podship/registry.yaml. podship reads it before it changes
// anything, so two projects never take the same directory, compose project,
// port, domain, database or backup slot.
//
// It also holds the schedule of the machine: the time of the nightly
// scheduler run (`scheduler:`) and the jobs it runs (`jobs:`). The podship
// scheduler agent reads the jobs from here; nothing else is registered with
// launchd or systemd per environment.

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

/// The nightly scheduler run of a machine.
class SchedulerSettings {
  SchedulerSettings({this.at = defaultAt});

  factory SchedulerSettings.fromMap(Map? m) =>
      SchedulerSettings(at: validTime('${m?['at'] ?? defaultAt}'));

  /// The default time of the nightly run, machine local time.
  static const defaultAt = '03:00';

  /// `HH:MM`, machine local time.
  final String at;

  int get hour => int.parse(at.substring(0, 2));
  int get minute => int.parse(at.substring(3, 5));

  Map<String, Object?> toMap() => {'at': at};

  /// [t] as `HH:MM`, or a [RegistryConflict] when it is not a time.
  static String validTime(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
    if (m == null) throw RegistryConflict('"$t" is not a time (HH:MM)');
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    if (h > 23 || mi > 59) throw RegistryConflict('"$t" is not a time (HH:MM)');
    return '${h.toString().padLeft(2, '0')}:${m[2]}';
  }
}

/// What the scheduler runs.
enum JobKind {
  /// `podship agent backup --conf <conf>` on the server that holds the data.
  backup,

  /// `podship backup pull` on the machine that keeps the off-site copies.
  pull,

  /// A project's own nightly command (`scheduled:` in `podship.yaml`): argv
  /// run in a folder of the current release, after backups and pulls.
  command,
}

/// One scheduled job. The registry holds everything the job needs, so the
/// scheduler runs it on a machine with no `podship.yaml`.
class ScheduledJob {
  ScheduledJob({
    required this.kind,
    required this.project,
    required this.env,
    this.enabled = true,
    this.script,
    this.conf,
    this.log,
    this.projectDir,
    this.path,
    this.note,
    this.name,
    this.run,
    this.cwd,
  });

  factory ScheduledJob.fromMap(Map m) => ScheduledJob(
    kind: JobKind.values.byName('${m['kind']}'),
    project: '${m['project']}',
    env: '${m['env']}',
    enabled: m['enabled'] != false,
    script: m['script'] as String?,
    conf: m['conf'] as String?,
    log: m['log'] as String?,
    projectDir: m['project_dir'] as String?,
    path: m['path'] as String?,
    note: m['note'] as String?,
    name: m['name'] as String?,
    run: m['run'] is List ? [for (final x in m['run'] as List) '$x'] : null,
    cwd: m['cwd'] as String?,
  );

  final JobKind kind;
  final String project;
  final String env;
  final bool enabled;

  /// Backup: its settings file and its log file. [script] is the bash
  /// script of older podships; registries keep it, the scheduler ignores it.
  final String? script;
  final String? conf;
  final String? log;

  /// Pull: the project root that holds `podship.yaml`.
  final String? projectDir;

  /// The PATH the job runs with (Docker, age, zstd, podship).
  final String? path;

  /// Where the job came from, for people (`migrated from …`).
  final String? note;

  /// Command: its name, argv and working folder.
  final String? name;
  final List<String>? run;
  final String? cwd;

  /// `backup:project/env`, `pull:project/env` or
  /// `command:project/env/name`.
  String get id => kind == JobKind.command
      ? '${kind.name}:$project/$env/$name'
      : '${kind.name}:$project/$env';
  String get envKey => '$project/$env';

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'project': project,
    'env': env,
    'enabled': enabled,
    'script': ?script,
    'conf': ?conf,
    'log': ?log,
    'project_dir': ?projectDir,
    'path': ?path,
    'note': ?note,
    'name': ?name,
    'run': ?run,
    'cwd': ?cwd,
  };
}

class Registry {
  Registry({
    Map<String, RegistryEntry>? entries,
    Map<String, ScheduledJob>? jobs,
    SchedulerSettings? scheduler,
    this.portMin = 20000,
    this.portMax = 20999,
  }) : entries = entries ?? {},
       jobs = jobs ?? {},
       scheduler = scheduler ?? SchedulerSettings();

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
    final jobs = <String, ScheduledJob>{};
    final j = doc['jobs'];
    if (j is YamlMap) {
      for (final e in j.entries) {
        final job = ScheduledJob.fromMap(e.value as Map);
        jobs[job.id] = job;
      }
    }
    return Registry(
      entries: entries,
      jobs: jobs,
      scheduler: SchedulerSettings.fromMap(doc['scheduler'] as Map?),
      portMin: range is YamlList ? range[0] as int : 20000,
      portMax: range is YamlList ? range[1] as int : 20999,
    );
  }

  final Map<String, RegistryEntry> entries;

  /// The jobs of the nightly scheduler run, by [ScheduledJob.id].
  final Map<String, ScheduledJob> jobs;

  /// The nightly run of this machine.
  SchedulerSettings scheduler;
  final int portMin;
  final int portMax;

  /// Adds or replaces [job].
  void putJob(ScheduledJob job) => jobs[job.id] = job;

  ScheduledJob? removeJob(String id) => jobs.remove(id);

  /// The jobs of one environment, backups first.
  List<ScheduledJob> jobsOf(String project, String env) => [
    for (final j in orderedJobs)
      if (j.project == project && j.env == env) j,
  ];

  /// Every job in run order: backups, then pulls; by id within a kind.
  List<ScheduledJob> get orderedJobs {
    final list = jobs.values.toList()
      ..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : a.id.compareTo(b.id);
      });
    return list;
  }

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

  /// Removes the entry and its jobs.
  RegistryEntry? remove(String key) {
    jobs.removeWhere((_, j) => j.envKey == key);
    return entries.remove(key);
  }

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
    b
      ..writeln(
        '# The nightly scheduler run (machine local time) and its jobs:',
      )
      ..writeln('# podship scheduler status | run-once | install.')
      ..writeln('scheduler:')
      ..writeln('  at: ${jsonEncode(scheduler.at)}')
      ..writeln('jobs:');
    final ids = jobs.keys.toList()..sort();
    if (ids.isEmpty) b.writeln('  {}');
    for (final id in ids) {
      b.writeln('  ${jsonEncode(id)}:');
      jobs[id]!.toMap().forEach((field, value) {
        b.writeln('    $field: ${jsonEncode(value)}');
      });
    }
    return b.toString();
  }
}
