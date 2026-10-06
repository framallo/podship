// Changes to outside services (DNS records, tunnel ingress, Access apps,
// SES identities) as data: a plan with before and after, a stable plan id,
// and an apply that undoes what it did when a later change fails.
//
// Flow: a planner reads the current state (through read-only clients) and
// returns a [ChangeSet]. `--plan` prints it. Applying needs an approval:
// `--yes` or a confirmation in the terminal, or in a console the owner's
// approval of that exact plan id. Before applying, podship plans again; if
// the id differs, the world changed since the approval and nothing runs.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../util/log.dart';

enum ChangeKind { create, update, delete, unchanged }

/// Undoes one applied change.
class Undo {
  Undo(this.title, this.run, {this.data = const {}});
  final String title;
  final Future<void> Function() run;

  /// What the undo would do, for the history record.
  final Map<String, Object?> data;
}

/// One change to one resource.
class Change {
  Change({
    required this.kind,
    required this.resource,
    required this.key,
    this.before,
    this.after,
    this.note,
    this.apply,
  });

  /// Nothing to do: the resource is already as wanted.
  Change.unchanged(this.resource, this.key, {String? state, this.note})
    : kind = ChangeKind.unchanged,
      before = state == null ? null : {'summary': state},
      after = state == null ? null : {'summary': state},
      apply = null;

  final ChangeKind kind;

  /// `dns_record`, `tunnel_ingress`, `tunnel_config_file`, `access_app`,
  /// `ses_identity`, `ses_mail_from`, `registry`.
  final String resource;

  /// What it is about, like `CNAME app.example.com`.
  final String key;

  /// The state before and after, with a one-line `summary`. No secrets.
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;

  /// Why, or what to know (shown under the change).
  final String? note;

  /// Does the change and returns how to undo it (null: nothing to undo).
  final Future<Undo?> Function()? apply;

  String get symbol => switch (kind) {
    ChangeKind.create => '+',
    ChangeKind.update => '~',
    ChangeKind.delete => '-',
    ChangeKind.unchanged => '=',
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'resource': resource,
    'key': key,
    'before': ?before,
    'after': ?after,
    'note': ?note,
  };
}

/// A check that is not a change: TLS coverage, SES sandbox, health.
class PlanCheck {
  PlanCheck(this.name, this.ok, this.detail);
  final String name;

  /// true: fine; false: a problem that stops nothing but needs attention.
  final bool ok;
  final String detail;
  Map<String, Object?> toJson() => {'name': name, 'ok': ok, 'detail': detail};
}

/// A plan of changes.
class ChangeSet {
  ChangeSet(this.title, this.changes, {this.checks = const []});
  final String title;
  final List<Change> changes;
  final List<PlanCheck> checks;

  List<Change> get pending => [
    for (final c in changes)
      if (c.kind != ChangeKind.unchanged) c,
  ];

  bool get isEmpty => pending.isEmpty;

  /// A stable id of the pending changes: the same state and config give
  /// the same id, so an approval names exactly what will run.
  String get id {
    final canon = jsonEncode([for (final c in pending) _canonical(c.toJson())]);
    return sha256.convert(utf8.encode(canon)).toString().substring(0, 12);
  }

  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is List) return [for (final x in v) _canonical(x)];
    return v;
  }

  ChangeSet operator +(ChangeSet other) => ChangeSet(
    title,
    [...changes, ...other.changes],
    checks: [...checks, ...other.checks],
  );

  Map<String, int> get counts => {
    for (final k in ChangeKind.values)
      k.name: changes.where((c) => c.kind == k).length,
  };

  Map<String, Object?> toJson() => {
    'title': title,
    'plan_id': id,
    'changes': [for (final c in changes) c.toJson()],
    'checks': [for (final c in checks) c.toJson()],
    'counts': counts,
  };

  /// The plan as text: one block per change, with before and after.
  String render() {
    final b = StringBuffer('Plan: $title (plan $id)\n');
    if (changes.isEmpty) b.writeln('  (nothing to manage)');
    for (final c in changes) {
      b.writeln('  ${c.symbol} ${c.resource.padRight(18)} ${c.key}');
      String s(Map<String, Object?>? m) =>
          m == null ? '(none)' : '${m['summary'] ?? jsonEncode(m)}';
      switch (c.kind) {
        case ChangeKind.create:
          b.writeln('      after:  ${s(c.after)}');
        case ChangeKind.update:
          b.writeln('      before: ${s(c.before)}');
          b.writeln('      after:  ${s(c.after)}');
        case ChangeKind.delete:
          b.writeln('      before: ${s(c.before)}');
        case ChangeKind.unchanged:
          if (c.after != null) b.writeln('      is:     ${s(c.after)}');
      }
      if (c.note != null) b.writeln('      note:   ${c.note}');
    }
    if (checks.isNotEmpty) {
      b.writeln('Checks:');
      for (final c in checks) {
        b.writeln('  ${c.ok ? 'ok' : '!!'} ${c.name}: ${c.detail}');
      }
    }
    final n = counts;
    b.writeln(
      '${n['create']} to create, ${n['update']} to update, '
      '${n['delete']} to delete, ${n['unchanged']} unchanged.',
    );
    return b.toString();
  }
}

/// A change failed; the ones before it were undone.
class ApplyFailed implements Exception {
  ApplyFailed(this.change, this.error, this.undone, this.undoFailures);
  final Change change;
  final Object error;
  final List<String> undone;
  final List<String> undoFailures;
  @override
  String toString() =>
      '${change.symbol} ${change.resource} ${change.key} failed: $error'
      '${undone.isEmpty ? '' : '; undone: ${undone.join(', ')}'}'
      '${undoFailures.isEmpty ? '' : '; COULD NOT UNDO: ${undoFailures.join(', ')}'}';
}

/// What an apply did, for the result and the history record.
class ApplyReport {
  ApplyReport(this.planId, this.applied, this.undos);
  final String planId;
  final List<Change> applied;
  final List<Undo> undos;
  Map<String, Object?> toJson() => {
    'plan_id': planId,
    'applied': [for (final c in applied) c.toJson()],
    'undo': [
      for (final u in undos.reversed) {'title': u.title, ...u.data},
    ],
  };
}

/// Applies the pending changes of [set] in order. When one fails, undoes
/// the applied ones in reverse order and throws [ApplyFailed].
Future<ApplyReport> applyChanges(ChangeSet set, Log log) async {
  final applied = <Change>[];
  final undos = <Undo>[];
  for (final c in set.pending) {
    log.info('${c.symbol} ${c.resource} ${c.key}');
    try {
      final u = await c.apply!();
      applied.add(c);
      if (u != null) undos.add(u);
    } catch (e) {
      log.error('${c.resource} ${c.key}: $e');
      final undone = <String>[];
      final failures = <String>[];
      for (final u in undos.reversed) {
        try {
          log.warn('undo: ${u.title}');
          await u.run();
          undone.add(u.title);
        } catch (e2) {
          failures.add('${u.title} ($e2)');
          log.error('undo failed: ${u.title}: $e2');
        }
      }
      throw ApplyFailed(c, e, undone, failures);
    }
  }
  return ApplyReport(set.id, applied, undos);
}
