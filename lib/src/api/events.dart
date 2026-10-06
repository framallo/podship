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
