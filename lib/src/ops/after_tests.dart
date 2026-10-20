// What a deploy says about the suites that ran after the switch
// (`blocks: false`). A failure is reported, never rolled back: one
// notification for the deploy, one issue per failed suite in the project's
// tracker, and `tests_after` in the history record.
import 'dart:io';

import '../api/events.dart';
import '../config/config.dart';
import '../integrations/secrets.dart';
import '../notify/notify.dart';
import '../util/log.dart';
import 'app_ops.dart';

/// How the after-deploy suites ended: their results, or [error] when they
/// could not run at all.
class AfterTestsOutcome {
  AfterTestsOutcome({
    required this.results,
    required this.release,
    this.recordPath,
    this.error,
  });
  final List<SuiteResult> results;
  final String release;

  /// The record on the server, when it was written.
  final String? recordPath;
  final String? error;

  List<SuiteResult> get failed => [
    for (final r in results)
      if (!r.ok) r,
  ];
  bool get ok => error == null && failed.isEmpty;
}

/// An issue to open in the project's tracker.
class IssueDraft {
  IssueDraft({required this.title, required this.body});
  final String title;
  final String body;
}

/// The report of an [AfterTestsOutcome]: the notification to send (null
/// when every suite passed), the issues to open and `tests_after` for the
/// history record.
class AfterTestsReport {
  AfterTestsReport({
    required this.notification,
    required this.issues,
    required this.data,
  });
  final Notification? notification;
  final List<IssueDraft> issues;
  final Map<String, Object?> data;
}

/// Builds the report of [outcome] for [project] on [env] at commit [sha].
AfterTestsReport afterTestsReport(
  AfterTestsOutcome outcome, {
  required String project,
  required String env,
  required String sha,
  String? host,
}) {
  final failed = outcome.failed;
  final data = <String, Object?>{
    'ok': outcome.ok,
    'suites': [for (final r in outcome.results) r.toJson()],
    'record': ?outcome.recordPath,
    'error': ?outcome.error,
    'issues': <Map<String, Object?>>[],
  };
  if (outcome.ok) {
    return AfterTestsReport(notification: null, issues: const [], data: data);
  }
  final short = sha.length > 7 ? sha.substring(0, 7) : sha;
  final release = outcome.release;
  if (outcome.error != null) {
    return AfterTestsReport(
      notification: Notification(
        event: NotifyEvent.afterTestsFailed,
        title: 'tests after deploy did not run ($project/$env)',
        body: [
          'release $release stays (these suites never roll back)',
          outcome.error!,
          'commit $short',
        ].join('\n'),
        ok: false,
        project: project,
        env: env,
        host: host,
        release: release,
        data: {'error': outcome.error, 'sha': sha},
      ),
      issues: const [],
      data: data,
    );
  }
  String counts(SuiteResult r) => r.timedOut
      ? 'timed out'
      : '${r.failed} failed, ${r.passed} passed'
            '${r.exitCode == null ? '' : ', exit code ${r.exitCode}'}';
  final notification = Notification(
    event: NotifyEvent.afterTestsFailed,
    title:
        'tests after deploy FAILED ($project/$env): '
        '${failed.map((r) => r.suite).join(', ')}',
    body: [
      'release $release stays (these suites never roll back)',
      for (final r in failed) '${r.suite}: ${counts(r)}',
      'commit $short',
    ].join('\n'),
    ok: false,
    project: project,
    env: env,
    host: host,
    release: release,
    data: {
      'suites': [for (final r in failed) r.suite],
      'sha': sha,
    },
  );
  final issues = <IssueDraft>[
    for (final r in failed)
      IssueDraft(
        title: 'Tests after deploy: ${r.suite} failed on $env ($release)',
        body: [
          'The suite `${r.suite}` (`blocks: false`) failed after the switch '
              'to `$release` on `$env`. The release stays.',
          '',
          '- Commit: `$short`',
          '- Result: ${counts(r)}',
          if (r.failures.isNotEmpty) ...[
            '- Failed tests:',
            for (final f in r.failures.take(20)) '  - $f',
            if (r.failures.length > 20)
              '  - and ${r.failures.length - 20} more',
          ],
          if (r.log != null && _tail(r.log!).trim().isNotEmpty) ...[
            '',
            'Log tail:',
            '',
            '```',
            _tail(r.log!).trimRight(),
            '```',
          ],
        ].join('\n'),
      ),
  ];
  return AfterTestsReport(
    notification: notification,
    issues: issues,
    data: data,
  );
}

/// Reports [outcome]: `tests_after` into [history], the notification, and
/// one issue per failed suite when the project names a tracker and the
/// token is in the secret store. Never throws.
Future<void> reportAfterTests(
  AfterTestsOutcome outcome, {
  required PodshipConfig config,
  required String env,
  required String? host,
  required String sha,
  required Notifier notifier,
  required Integrations integrations,
  required Log log,
  required Map<String, Object?> history,
}) async {
  final report = afterTestsReport(
    outcome,
    project: config.project,
    env: env,
    sha: sha,
    host: host,
  );
  history['tests_after'] = report.data;
  final notification = report.notification;
  if (notification == null) return;
  await notifier.send(notification, log: log);
  final tracker = config.issues;
  if (tracker == null || report.issues.isEmpty) return;
  final client = integrations.issues(tracker);
  if (client == null) {
    log.warn(
      'issues: no token for ${tracker.url} (BOCETO_TOKEN, or `$bocetoTokenKey` in the secret store); no issue opened for the failed suites',
    );
    return;
  }
  final opened = report.data['issues'] as List<Map<String, Object?>>;
  for (final draft in report.issues) {
    try {
      final made = await client.create(title: draft.title, body: draft.body);
      opened.add({'number': made.number, 'url': made.url});
      log.info('opened issue #${made.number}: ${made.url}');
    } catch (e) {
      log.warn('could not open an issue for a failed suite: $e');
    }
  }
}

/// The last 40 lines of [path], or empty.
String _tail(String path) {
  final f = File(path);
  if (!f.existsSync()) return '';
  final lines = f.readAsLinesSync();
  return lines.skip(lines.length > 40 ? lines.length - 40 : 0).join('\n');
}
