// Events: what an operation does, as it happens.
//
// Every operation emits a stream of these. The CLI renders them as text or
// as JSON lines (`--json`); a UI can show them live. Events never carry
// secret values.

/// The level of a [LogLine].
enum LogLevel { info, detail, ok, warn, error, output }

sealed class PodshipEvent {
  PodshipEvent() : time = DateTime.now().toUtc();
  final DateTime time;

  String get type;

  Map<String, Object?> fields();

  Map<String, Object?> toJson() => {
    'type': type,
    'time': time.toIso8601String(),
    ...fields(),
  };
}

/// An operation began.
class OperationStarted extends PodshipEvent {
  OperationStarted(
    this.operation, {
    this.project,
    this.env,
    this.host,
    this.dryRun = false,
  });
  final String operation;
  final String? project;
  final String? env;
  final String? host;
  final bool dryRun;
  @override
  String get type => 'operation_started';
  @override
  Map<String, Object?> fields() => {
    'operation': operation,
    'project': ?project,
    'env': ?env,
    'host': ?host,
    'dry_run': dryRun,
  };
}

/// The plan of an operation, before it runs (and the whole output of a
/// `--dry-run`).
class PlanReady extends PodshipEvent {
  PlanReady(this.title, this.steps, this.text);
  final String title;

  /// Step titles, in order.
  final List<String> steps;

  /// The plan as text, as `--dry-run` prints it.
  final String text;
  @override
  String get type => 'plan';
  @override
  Map<String, Object?> fields() => {
    'title': title,
    'steps': steps,
    'text': text,
  };
}

class StepStarted extends PodshipEvent {
  StepStarted(this.index, this.total, this.title, {this.recovery = false});
  final int index;
  final int total;
  final String title;

  /// Whether this step undoes a failure.
  final bool recovery;
  @override
  String get type => 'step_started';
  @override
  Map<String, Object?> fields() => {
    'index': index,
    'total': total,
    'title': title,
    if (recovery) 'recovery': true,
  };
}

class StepFinished extends PodshipEvent {
  StepFinished(this.index, this.title, this.duration);
  final int index;
  final String title;
  final Duration duration;
  @override
  String get type => 'step_finished';
  @override
  Map<String, Object?> fields() => {
    'index': index,
    'title': title,
    'duration_ms': duration.inMilliseconds,
  };
}

class StepFailed extends PodshipEvent {
  StepFailed(this.index, this.title, this.error);
  final int index;
  final String title;
  final String error;
  @override
  String get type => 'step_failed';
  @override
  Map<String, Object?> fields() => {
    'index': index,
    'title': title,
    'error': error,
  };
}

/// A line of output: from podship itself, or from a command on a server.
class LogLine extends PodshipEvent {
  LogLine(this.text, {this.level = LogLevel.info, this.stderr = false});
  final String text;
  final LogLevel level;
  final bool stderr;
  @override
  String get type => 'log';
  @override
  Map<String, Object?> fields() => {
    'level': level.name,
    'text': text,
    if (stderr) 'stderr': true,
  };
}

/// A test suite began.
class SuiteStarted extends PodshipEvent {
  SuiteStarted(this.suite, this.command);
  final String suite;
  final String command;
  @override
  String get type => 'suite_started';
  @override
  Map<String, Object?> fields() => {'suite': suite, 'command': command};
}

/// A test failed (as the test runner names it).
class TestFailed extends PodshipEvent {
  TestFailed(this.suite, this.test);
  final String suite;
  final String test;
  @override
  String get type => 'test_failed';
  @override
  Map<String, Object?> fields() => {'suite': suite, 'test': test};
}

/// A test suite ended.
class SuiteFinished extends PodshipEvent {
  SuiteFinished(this.result);
  final SuiteResult result;
  @override
  String get type => 'suite_finished';
  @override
  Map<String, Object?> fields() => result.toJson();
}

/// The outcome of one test suite.
class SuiteResult {
  SuiteResult({
    required this.suite,
    required this.ok,
    required this.duration,
    this.passed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.failures = const [],
    this.exitCode,
    this.timedOut = false,
    this.log,
  });

  factory SuiteResult.fromJson(Map<String, Object?> j) => SuiteResult(
    suite: '${j['suite']}',
    ok: j['ok'] == true,
    duration: Duration(milliseconds: (j['duration_ms'] as num? ?? 0).toInt()),
    passed: (j['passed'] as num? ?? 0).toInt(),
    skipped: (j['skipped'] as num? ?? 0).toInt(),
    failed: (j['failed'] as num? ?? 0).toInt(),
    failures: [for (final f in (j['failures'] as List? ?? const [])) '$f'],
    exitCode: (j['exit_code'] as num?)?.toInt(),
    timedOut: j['timed_out'] == true,
    log: j['log'] as String?,
  );

  final String suite;
  final bool ok;
  final Duration duration;
  final int passed;
  final int skipped;
  final int failed;

  /// Names of failed tests, as the runner printed them.
  final List<String> failures;
  final int? exitCode;
  final bool timedOut;

  /// Where the full output is kept.
  final String? log;

  Map<String, Object?> toJson() => {
    'suite': suite,
    'ok': ok,
    'duration_ms': duration.inMilliseconds,
    'passed': passed,
    'skipped': skipped,
    'failed': failed,
    if (failures.isNotEmpty) 'failures': failures,
    'exit_code': ?exitCode,
    if (timedOut) 'timed_out': true,
    'log': ?log,
  };
}

/// The end of an operation.
class OperationFinished extends PodshipEvent {
  OperationFinished(this.result);
  final OperationResult result;
  @override
  String get type => 'result';
  @override
  Map<String, Object?> fields() => result.toJson();
}

/// What an operation did.
class OperationResult {
  OperationResult({
    required this.operation,
    required this.ok,
    required this.duration,
    this.project,
    this.env,
    this.host,
    this.release,
    this.previousRelease,
    this.error,
    this.dryRun = false,
    this.data = const {},
    this.historyPath,
  });

  final String operation;
  final bool ok;
  final Duration duration;
  final String? project;
  final String? env;
  final String? host;

  /// The release that runs after the operation, when it changes releases.
  final String? release;

  /// The release that ran before it.
  final String? previousRelease;
  final String? error;
  final bool dryRun;

  /// Operation-specific values, like a backup stamp.
  final Map<String, Object?> data;

  /// Where the server keeps the history record of this operation.
  final String? historyPath;

  factory OperationResult.fromJson(Map<String, Object?> j) => OperationResult(
    operation: '${j['operation']}',
    ok: j['ok'] == true,
    duration: Duration(milliseconds: (j['duration_ms'] as num? ?? 0).toInt()),
    project: j['project'] as String?,
    env: j['env'] as String?,
    host: j['host'] as String?,
    release: j['release'] as String?,
    previousRelease: j['previous_release'] as String?,
    error: j['error'] as String?,
    dryRun: j['dry_run'] == true,
    data: (j['data'] as Map?)?.cast<String, Object?>() ?? const {},
    historyPath: j['history'] as String?,
  );

  /// A copy with the history record path.
  OperationResult withHistory(String path) => OperationResult(
    operation: operation,
    ok: ok,
    duration: duration,
    project: project,
    env: env,
    host: host,
    release: release,
    previousRelease: previousRelease,
    error: error,
    dryRun: dryRun,
    data: data,
    historyPath: path,
  );

  Map<String, Object?> toJson() => {
    'operation': operation,
    'ok': ok,
    'duration_ms': duration.inMilliseconds,
    'project': ?project,
    'env': ?env,
    'host': ?host,
    'release': ?release,
    'previous_release': ?previousRelease,
    'error': ?error,
    if (dryRun) 'dry_run': true,
    if (data.isNotEmpty) 'data': data,
    'history': ?historyPath,
  };
}

/// Reads an event written by [PodshipEvent.toJson] (from a console's stream,
/// for example). Unknown types become a [LogLine] with the raw JSON.
PodshipEvent eventFromJson(Map<String, Object?> j) {
  String s(String k) => '${j[k] ?? ''}';
  int n(String k) => (j[k] as num? ?? 0).toInt();
  final e = switch (j['type']) {
    'operation_started' => OperationStarted(
      s('operation'),
      project: j['project'] as String?,
      env: j['env'] as String?,
      host: j['host'] as String?,
      dryRun: j['dry_run'] == true,
    ),
    'plan' => PlanReady(s('title'), [
      for (final x in (j['steps'] as List? ?? const [])) '$x',
    ], s('text')),
    'step_started' => StepStarted(
      n('index'),
      n('total'),
      s('title'),
      recovery: j['recovery'] == true,
    ),
    'step_finished' => StepFinished(
      n('index'),
      s('title'),
      Duration(milliseconds: n('duration_ms')),
    ),
    'step_failed' => StepFailed(n('index'), s('title'), s('error')),
    'log' => LogLine(
      s('text'),
      level: LogLevel.values.firstWhere(
        (l) => l.name == j['level'],
        orElse: () => LogLevel.info,
      ),
      stderr: j['stderr'] == true,
    ),
    'suite_started' => SuiteStarted(s('suite'), s('command')),
    'test_failed' => TestFailed(s('suite'), s('test')),
    'suite_finished' => SuiteFinished(SuiteResult.fromJson(j)),
    'result' => OperationFinished(OperationResult.fromJson(j)),
    _ => LogLine('$j'),
  };
  return e;
}
