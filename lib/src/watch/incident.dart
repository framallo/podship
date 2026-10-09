// The incident state machine of `podship watch`. Pure: no IO, no clock.
//
// Per target, each run gives one [Outcome]:
//
//   ok ──fail──▶ suspect (1 failure, silent)
//   suspect ──fail──▶ down: the incident opens, ONE alert, heal attempt 1
//   down ──fail──▶ heal attempt 2 after the backoff; then "still down" once
//   down ──pass──▶ ok: ONE "recovered" message with the downtime
//   suspect ──pass──▶ ok (silent)
//
// An `unknown` run (this machine has no internet) changes nothing.

import 'dart:convert';

/// The result of the checks of one target in one run.
enum Outcome { pass, fail, unknown }

/// What the watch remembers about one target between runs.
class TargetState {
  TargetState({
    this.fails = 0,
    this.firstFail,
    this.incident,
    this.heals = 0,
    this.lastHeal,
    this.gaveUp = false,
    this.lastProblem,
    this.lastRun,
    this.lastOk,
  });

  factory TargetState.fromJson(Map m) => TargetState(
    fails: (m['fails'] as num?)?.toInt() ?? 0,
    firstFail: _time(m['first_fail']),
    incident: m['incident'] as String?,
    heals: (m['heals'] as num?)?.toInt() ?? 0,
    lastHeal: _time(m['last_heal']),
    gaveUp: m['gave_up'] as bool? ?? false,
    lastProblem: m['last_problem'] as String?,
    lastRun: _time(m['last_run']),
    lastOk: _time(m['last_ok']),
  );

  /// Failed runs in a row.
  int fails;

  /// The first failed run of the current streak: the start of the downtime.
  DateTime? firstFail;

  /// The id of the open incident (alert sent), or null.
  String? incident;

  /// Heal attempts in the open incident.
  int heals;
  DateTime? lastHeal;

  /// The "still down" message of the open incident was sent.
  bool gaveUp;
  String? lastProblem;
  DateTime? lastRun;
  DateTime? lastOk;

  bool get isDown => incident != null;

  Map<String, Object?> toJson() => {
    'fails': fails,
    'first_fail': ?firstFail?.toUtc().toIso8601String(),
    'incident': ?incident,
    'heals': heals,
    'last_heal': ?lastHeal?.toUtc().toIso8601String(),
    if (gaveUp) 'gave_up': true,
    'last_problem': ?lastProblem,
    'last_run': ?lastRun?.toUtc().toIso8601String(),
    'last_ok': ?lastOk?.toUtc().toIso8601String(),
  };

  TargetState copy() =>
      TargetState.fromJson(jsonDecode(jsonEncode(toJson())) as Map);
}

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// The rules of one machine (from its registry's `watch:`).
class IncidentRules {
  const IncidentRules({
    this.alertAfter = 2,
    this.healAttempts = 2,
    this.healBackoff = const Duration(minutes: 6),
  });
  final int alertAfter;
  final int healAttempts;
  final Duration healBackoff;
}

/// What one run must do for one target.
class Decision {
  Decision({
    this.alertDown = false,
    this.heal = false,
    this.healAttempt = 0,
    this.alertStillDown = false,
    this.alertRecovered = false,
    this.downtime,
    this.incident,
  });

  /// Send the "down" alert (once per incident).
  final bool alertDown;

  /// Run heal attempt [healAttempt] now.
  final bool heal;
  final int healAttempt;

  /// The heal attempts are used up and it still fails (once per incident).
  final bool alertStillDown;

  /// Send "recovered" with [downtime] (once per incident).
  final bool alertRecovered;
  final Duration? downtime;

  /// The incident this decision belongs to.
  final String? incident;

  bool get isNothing =>
      !alertDown && !heal && !alertStillDown && !alertRecovered;
}

/// The id of an incident that starts at [t] on [key].
String incidentId(String key, DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z-$key';
}

/// Applies [outcome] at [now] to [s] (changed in place) and says what to do.
/// [canHeal]: the target runs on this machine and may be healed.
/// [mayAlert]: false for a cross-watch copy whose owner machine is alive.
Decision step(
  TargetState s,
  Outcome outcome,
  DateTime now, {
  required String key,
  required bool canHeal,
  IncidentRules rules = const IncidentRules(),
  String? problem,
  bool mayAlert = true,
}) {
  if (outcome == Outcome.unknown) return Decision(incident: s.incident);
  s.lastRun = now;
  if (outcome == Outcome.pass) {
    final open = s.incident;
    final down = open == null || s.firstFail == null
        ? null
        : now.difference(s.firstFail!);
    s
      ..fails = 0
      ..firstFail = null
      ..incident = null
      ..heals = 0
      ..lastHeal = null
      ..gaveUp = false
      ..lastProblem = null
      ..lastOk = now;
    return open == null
        ? Decision()
        : Decision(alertRecovered: true, downtime: down, incident: open);
  }
  // A failed run.
  s
    ..fails += 1
    ..firstFail ??= now
    ..lastProblem = problem;
  if (s.fails < rules.alertAfter) return Decision();
  // A cross-watch copy while the owner machine is alive: the owner alerts.
  // The streak keeps counting; the copy opens the incident (and alerts)
  // at the first run that finds the owner's heartbeat stale.
  if (s.incident == null && !mayAlert) return Decision();
  var alertDown = false;
  if (s.incident == null) {
    s.incident = incidentId(key, s.firstFail!);
    alertDown = true;
  }
  var heal = false;
  if (canHeal && s.heals < rules.healAttempts) {
    final last = s.lastHeal;
    if (last == null || now.difference(last) >= rules.healBackoff) {
      s
        ..heals += 1
        ..lastHeal = now;
      heal = true;
    }
  }
  var stillDown = false;
  if (!heal && !alertDown && !s.gaveUp) {
    // Nothing more to try: the heals are used up (and the last one had its
    // backoff to work), or this machine may not heal.
    final used = !canHeal || s.heals >= rules.healAttempts;
    final settled =
        s.lastHeal == null || now.difference(s.lastHeal!) >= rules.healBackoff;
    if (used && settled && canHeal) {
      s.gaveUp = true;
      stillDown = true;
    }
  }
  return Decision(
    alertDown: alertDown,
    heal: heal,
    healAttempt: heal ? s.heals : 0,
    alertStillDown: stillDown,
    incident: s.incident,
  );
}

/// `<home>/watch/state.json`: the state of every target.
class WatchState {
  WatchState({Map<String, TargetState>? targets, this.lastRun})
    : targets = targets ?? {};

  factory WatchState.fromJson(Map m) => WatchState(
    targets: {
      for (final e in ((m['targets'] as Map?) ?? const {}).entries)
        '${e.key}': TargetState.fromJson(e.value as Map),
    },
    lastRun: _time(m['last_run']),
  );

  final Map<String, TargetState> targets;
  DateTime? lastRun;

  Map<String, Object?> toJson() => {
    'last_run': ?lastRun?.toUtc().toIso8601String(),
    'targets': {for (final e in targets.entries) e.key: e.value.toJson()},
  };
}
