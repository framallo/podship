// watch install|uninstall|status|history|run.
//
// The watch runs inside the scheduler agent of each machine, every
// `watch.interval` seconds: `scheduler tick` calls it before the nightly
// jobs. These commands write its targets and read what it saw.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../ops/context.dart';
import '../ops/watch_ops.dart';
import '../remote/ssh.dart';
import '../watch/runner.dart';
import 'base.dart';

abstract class _WatchFleetCommand extends PodshipCommand {
  _WatchFleetCommand() {
    argParser.addOption(
      'machine',
      abbr: 'm',
      help: 'One machine of the fleet (default: all of them).',
    );
  }

  @override
  bool get takesEnv => false;

  /// The machines to ask: the fleet of `~/.podship/config.yaml`, else this
  /// machine (the home of a `host: local` environment, or ~/podship).
  List<FleetMachine> machines() {
    final fleet = FleetConfig.load();
    var list = fleet.machines;
    if (list.isEmpty) {
      final local = configOrEmpty.environments.values
          .where((e) => isLocalHost(e.host))
          .firstOrNull;
      list = [
        FleetMachine(
          name: Platform.localHostname,
          host: localHost,
          home:
              local?.podshipHome ??
              '${Platform.environment['HOME'] ?? ''}/podship',
        ),
      ];
    }
    final only = argResults!['machine'] as String?;
    if (only == null) return list;
    final m = list.where((m) => m.name == only).toList();
    if (m.isEmpty) {
      throw Aborted(
        'no machine "$only" (${list.map((m) => m.name).join(', ')})',
      );
    }
    return m;
  }

  Future<List<WatchMachineStatus>> statuses({int n = 20}) =>
      Future.wait([for (final m in machines()) watchStatus(ctx, m, n: n)]);
}

class WatchInstallCommand extends PodshipCommand {
  WatchInstallCommand({this.remove = false}) {
    argParser.addMultiOption(
      'env',
      abbr: 'e',
      help: 'The environments (default: all of podship.yaml).',
    );
  }
  final bool remove;

  @override
  String get name => remove ? 'uninstall' : 'install';
  @override
  String get description => remove
      ? 'Stop watching environments: remove their targets from every machine of the fleet.'
      : 'Watch environments: write their public checks into the registry of the machine they run on '
            '(it heals them) and of every other machine of the fleet (cross-watch, alerts only). '
            'The fleet and the alert channels come from watch: in ~/.podship/config.yaml.';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;
  @override
  Future<int> execute() => runOp(
    api.watchInstall((argResults!['env'] as List<String>), remove: remove),
  );
}

class WatchStatusCommand extends _WatchFleetCommand {
  @override
  String get name => 'status';
  @override
  String get description =>
      'What each machine watches, the state of each target (ok, failing, DOWN), and the last run.';
  @override
  Future<int> execute() async {
    final all = await statuses(n: 0);
    if (this.json) {
      stdout.writeln(jsonEncode([for (final s in all) s.toJson()]));
      return 0;
    }
    for (final s in all) {
      stdout.writeln(
        '${s.machine}${s.error != null ? ': not reachable (${s.error})' : ''}',
      );
      if (s.error != null) continue;
      final w = s.watch;
      if (w.targets.isEmpty) {
        stdout.writeln('  no targets (podship watch install)');
        continue;
      }
      stdout.writeln(
        '  every ${w.interval} s; alert after ${w.alertAfter} failures; '
        '${w.healAttempts} heal attempts, ${w.healBackoff} s apart; '
        'engine ${w.engine.id}; channels: ${w.channels.isEmpty ? 'macos' : w.channels.keys.join(', ')}; '
        'last run ${s.state['last_run'] ?? 'never'}',
      );
      final states = (s.state['targets'] as Map?) ?? const {};
      final keys = w.targets.keys.toList()..sort();
      for (final k in keys) {
        final t = w.targets[k]!;
        final st = (states[k] as Map?) ?? const {};
        final fails = (st['fails'] as num?)?.toInt() ?? 0;
        final word = st['incident'] != null
            ? 'DOWN since ${st['first_fail']} (heals ${st['heals'] ?? 0})'
            : fails > 0
            ? 'failing ($fails)'
            : st['last_ok'] != null
            ? 'ok'
            : 'not checked yet';
        final role = t.owner
            ? (t.heals ? 'runs here, heals' : 'runs here, no heal')
            : 'cross-watch of ${t.machine}';
        stdout.writeln(
          '  ${k.padRight(28)} ${word.padRight(22)} $role, ${t.checks.length} check(s)',
        );
        final problem = st['last_problem'];
        if (problem != null) stdout.writeln('    $problem');
      }
    }
    return all.any((s) => s.error != null) ? 1 : 0;
  }
}

class WatchHistoryCommand extends _WatchFleetCommand {
  WatchHistoryCommand() {
    argParser
      ..addOption(
        'lines',
        abbr: 'n',
        defaultsTo: '30',
        help: 'Events per machine.',
      )
      ..addOption('target', help: 'Only this target (project/env).');
  }
  @override
  String get name => 'history';
  @override
  String get description =>
      'The incident log of each machine: down, engine start, heal, still down, recovered (with the downtime).';
  @override
  Future<int> execute() async {
    final n = int.tryParse(argResults!['lines'] as String) ?? 30;
    final only = argResults!['target'] as String?;
    final all = await statuses(n: n);
    final rows = <Map<String, Object?>>[
      for (final s in all)
        for (final e in s.events)
          if (only == null || e['target'] == only) {...e, 'machine': s.machine},
    ]..sort((a, b) => '${a['time']}'.compareTo('${b['time']}'));
    if (this.json) {
      stdout.writeln(jsonEncode(rows));
      return 0;
    }
    for (final s in all.where((s) => s.error != null)) {
      stderr.writeln('${s.machine}: not reachable (${s.error})');
    }
    if (rows.isEmpty) stdout.writeln('no incidents');
    for (final e in rows) {
      final t = DateTime.tryParse('${e['time']}')?.toLocal();
      final when = t == null
          ? '${e['time']}'
          : t.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
      final what = switch (e['event']) {
        'recovered' =>
          'recovered after ${formatDuration(Duration(seconds: (e['downtime_s'] as num?)?.toInt() ?? 0))}',
        'heal' =>
          'heal ${e['attempt'] ?? ''} ${e['ok'] == true ? 'ok' : 'failed'}: ${e['detail'] ?? ''}',
        'engine_start' =>
          'engine start ${e['ok'] == true ? 'ok' : 'failed'}: ${e['detail'] ?? ''}',
        'down' => 'DOWN: ${e['problem'] ?? ''}',
        'still_down' =>
          'STILL DOWN after ${e['attempt']} heal(s): ${e['problem'] ?? ''}',
        _ => '${e['event']}',
      };
      stdout.writeln(
        '$when  ${'${e['machine']}'.padRight(10)} ${'${e['target']}'.padRight(28)} $what',
      );
    }
    return 0;
  }
}

/// `watch run --home <home>`: one watch run on this machine now.
class WatchRunCommand extends PodshipCommand {
  WatchRunCommand() {
    argParser.addOption(
      'home',
      help: 'The podship home of this machine (its registry.yaml).',
      mandatory: true,
    );
  }
  @override
  String get name => 'run';
  @override
  String get description =>
      'Run the watch of this machine once now, as the agent does at each tick (checks, alerts, heal).';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    final run = await WatchRunner(
      argResults!['home'] as String,
      echo: stdout.writeln,
    ).run();
    return run == null ? 1 : 0;
  }
}

Command<int> watchGroup() => GroupCommand(
  'watch',
  'Watch the public URLs of every environment every few minutes, from its own machine and from the others; '
      'alert once per incident, heal on the machine that runs it (Docker engine, then podship restart), '
      'and send "recovered" with the downtime.',
  [
    WatchInstallCommand(),
    WatchInstallCommand(remove: true),
    WatchStatusCommand(),
    WatchHistoryCommand(),
    WatchRunCommand(),
  ],
);
