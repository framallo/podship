// Notifications: deploy started, deploy done, deploy failed (with the
// automatic rollback's result), rollback done, backup failed, scheduler
// job failed.
//
// [OperationWatcher] turns the events of one operation into
// [Notification]s. [Notifier] sends them to the channels of `notify:`:
// a macOS notification on the machine that runs the CLI, an email through
// SES, a webhook (JSON POST with an HMAC signature) and a Slack-compatible
// webhook. Every notification also goes to [Notifier.stream], which the
// console protocol's `subscribe_events` reads.
//
// A channel that fails or hangs never fails the operation: the error is a
// warning, and every send has a timeout. Notifications carry no secret
// values; the webhook secret and URLs with tokens come from
// `~/.podship/config.yaml` or the environment, never from events or logs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../api/events.dart';
import '../config/config.dart';
import '../integrations/http.dart';
import '../integrations/ses.dart';
import '../util/log.dart';

/// Something to tell the owner.
class Notification {
  Notification({
    required this.event,
    required this.title,
    required this.body,
    required this.ok,
    this.project,
    this.env,
    this.host,
    this.release,
    this.previousRelease,
    this.duration,
    this.data = const {},
    DateTime? time,
  }) : time = time ?? DateTime.now().toUtc();

  final NotifyEvent event;

  /// One line, like `deploy shop/staging done`.
  final String title;

  /// A few lines with the release, the duration and the health.
  final String body;
  final bool ok;
  final String? project;
  final String? env;
  final String? host;
  final String? release;
  final String? previousRelease;
  final Duration? duration;

  /// Extra values: the error, the rollback result, the stages.
  final Map<String, Object?> data;
  final DateTime time;

  Map<String, Object?> toJson() => {
    'event': event.id,
    'title': title,
    'body': body,
    'ok': ok,
    'time': time.toIso8601String(),
    'project': ?project,
    'env': ?env,
    'host': ?host,
    'release': ?release,
    'previous_release': ?previousRelease,
    if (duration != null) 'duration_ms': duration!.inMilliseconds,
    if (data.isNotEmpty) 'data': data,
  };

  /// A scheduler job failed (the scheduler calls this).
  static Notification schedulerJobFailed({
    required String job,
    required String error,
    String? project,
    String? env,
    String? host,
  }) => Notification(
    event: NotifyEvent.schedulerJobFailed,
    title: 'scheduler job $job failed${_where(project, env)}',
    body: error,
    ok: false,
    project: project,
    env: env,
    host: host,
    data: {'job': job, 'error': error},
  );
}

String _where(String? project, String? env) =>
    project == null ? '' : ' ($project${env == null ? '' : '/$env'})';

String _secs(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

/// One finished step, for the stage summary.
class StageTiming {
  StageTiming(
    this.title,
    this.duration, {
    this.ok = true,
    this.recovery = false,
  });
  final String title;
  final Duration duration;
  final bool ok;
  final bool recovery;

  Map<String, Object?> toJson() => {
    'title': title,
    'duration_ms': duration.inMilliseconds,
    if (!ok) 'ok': false,
    if (recovery) 'recovery': true,
  };
}

/// Watches the events of one operation and says what to announce. It also
/// keeps the stage timings, for the history record and the summary.
class OperationWatcher {
  String? _operation;
  String? _project, _env, _host;
  bool _healthy = false;
  bool _inRecovery = false;
  String? _rollbackTo;
  bool? _rollbackOk;
  final List<StageTiming> stages = [];
  final Map<int, DateTime> _started = {};

  /// Stage timings as JSON, for `data.steps` of the history record.
  List<Map<String, Object?>> get stagesJson => [
    for (final s in stages) s.toJson(),
  ];

  /// The notifications that [e] triggers (usually none).
  List<Notification> onEvent(PodshipEvent e) {
    switch (e) {
      case OperationStarted():
        _operation = e.operation;
        _project = e.project;
        _env = e.env;
        _host = e.host;
        if (e.operation == 'deploy' && !e.dryRun) {
          return [
            Notification(
              event: NotifyEvent.deployStarted,
              title: 'deploy started${_where(_project, _env)}',
              body: 'on ${e.host}',
              ok: true,
              project: _project,
              env: _env,
              host: _host,
            ),
          ];
        }
      case StepStarted():
        _started[e.index] = e.time;
        if (e.recovery) _inRecovery = true;
        if (e.recovery && e.title.startsWith('Roll back to ')) {
          _rollbackTo = e.title.substring('Roll back to '.length);
          _rollbackOk = null;
        }
      case StepFinished():
        stages.add(StageTiming(e.title, e.duration, recovery: _inRecovery));
        if (!_inRecovery && e.title.startsWith('Health check')) {
          _healthy = true;
        }
        if (_inRecovery &&
            (e.title.startsWith('Roll back to ') ||
                e.title.startsWith('Health check of '))) {
          _rollbackOk = true;
        }
      case StepFailed():
        final t0 = _started[e.index];
        stages.add(
          StageTiming(
            e.title,
            t0 == null ? Duration.zero : e.time.difference(t0),
            ok: false,
            recovery: _inRecovery,
          ),
        );
        if (_inRecovery && !e.title.startsWith('Mark ')) _rollbackOk = false;
      case OperationFinished():
        return _finished(e.result);
      case PlanReady():
      case LogLine():
      case SuiteStarted():
      case TestFailed():
      case SuiteFinished():
        break;
    }
    return const [];
  }

  List<Notification> _finished(OperationResult r) {
    if (r.dryRun) return const [];
    final op = _operation ?? r.operation;
    final where = _where(r.project, r.env);
    final dur = _secs(r.duration);
    final slow = _slowest();
    switch (op) {
      case 'deploy':
        if (r.ok) {
          return [
            Notification(
              event: NotifyEvent.deployDone,
              title: 'deploy done$where: ${r.release ?? '?'}',
              body: [
                'release ${r.release ?? '?'}',
                'took $dur${slow.isEmpty ? '' : ' ($slow)'}',
                'health: ${_healthy ? 'ok' : 'not checked'}',
              ].join('\n'),
              ok: true,
              project: r.project,
              env: r.env,
              host: r.host,
              release: r.release,
              previousRelease: r.previousRelease,
              duration: r.duration,
              data: {'healthy': _healthy, 'stages': stagesJson},
            ),
          ];
        }
        final rb = _rollbackTo == null
            ? 'no rollback (nothing was switched)'
            : _rollbackOk == true
            ? 'rolled back to $_rollbackTo: healthy'
            : _rollbackOk == false
            ? 'rollback to $_rollbackTo FAILED'
            : 'rollback to $_rollbackTo: unknown';
        return [
          Notification(
            event: NotifyEvent.deployFailed,
            title: 'deploy FAILED$where',
            body: [
              r.error ?? 'failed',
              rb,
              'running now: ${r.release ?? 'nothing'}',
              'took $dur',
            ].join('\n'),
            ok: false,
            project: r.project,
            env: r.env,
            host: r.host,
            release: r.release,
            previousRelease: r.previousRelease,
            duration: r.duration,
            data: {
              'error': ?r.error,
              'rollback': _rollbackTo == null
                  ? 'none'
                  : (_rollbackOk == true
                        ? 'ok'
                        : _rollbackOk == false
                        ? 'failed'
                        : 'unknown'),
              'rollback_to': ?_rollbackTo,
              'stages': stagesJson,
            },
          ),
        ];
      case 'rollback':
        return [
          Notification(
            event: NotifyEvent.rollbackDone,
            title: r.ok
                ? 'rollback done$where: ${r.release ?? '?'}'
                : 'rollback FAILED$where',
            body: r.ok
                ? 'from ${r.previousRelease ?? '?'} to ${r.release ?? '?'} in $dur'
                : '${r.error ?? 'failed'}\nrunning now: ${r.release ?? 'nothing'}',
            ok: r.ok,
            project: r.project,
            env: r.env,
            host: r.host,
            release: r.release,
            previousRelease: r.previousRelease,
            duration: r.duration,
            data: {'error': ?r.error},
          ),
        ];
      case 'backup now':
      case 'backup pull':
      case 'backup drill':
      case 'backup restore':
        if (r.ok) return const [];
        return [
          Notification(
            event: NotifyEvent.backupFailed,
            title: '$op FAILED$where',
            body: r.error ?? 'failed',
            ok: false,
            project: r.project,
            env: r.env,
            host: r.host,
            duration: r.duration,
            data: {'error': ?r.error, 'operation': op},
          ),
        ];
    }
    return const [];
  }

  /// The three slowest stages, like `build 132 s, tests 48 s`.
  String _slowest() {
    final main = [
      for (final s in stages)
        if (!s.recovery && s.duration.inSeconds >= 5) s,
    ]..sort((a, b) => b.duration.compareTo(a.duration));
    return main
        .take(3)
        .map((s) => '${shortStage(s.title)} ${_secs(s.duration)}')
        .join(', ');
  }
}

/// A short name for a step title, for summaries.
String shortStage(String title) {
  final t = title.toLowerCase();
  if (t.startsWith('run tests')) return 'tests';
  if (t.startsWith('build flutter web')) return 'web ${title.split(': ').last}';
  if (t.startsWith('build images')) return 'build';
  if (t.startsWith('upload')) return 'upload';
  if (t.startsWith('back up')) return 'backup';
  if (t.startsWith('switch')) return 'switch';
  if (t.startsWith('health')) return 'health';
  if (t.startsWith('export')) return 'export';
  if (t.startsWith('apply migrations')) return 'migrations';
  final first = title.split(' ').first.toLowerCase();
  return first;
}

/// Runs a program; tests replace it.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

Future<ProcessResult> _runProcess(String exe, List<String> args) =>
    Process.run(exe, args);

/// Sends notifications to the configured channels.
class Notifier {
  Notifier(
    this.config, {
    HttpTransport? transport,
    ProcessRunner? run,
    SesApi Function(String region)? ses,
    bool? macos,
    this.enabled = true,
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : transport =
           transport ?? IoTransport(timeout: const Duration(seconds: 10)),
       _run = run ?? _runProcess,
       _ses = ses,
       _macos = macos ?? Platform.isMacOS,
       _clock = clock ?? DateTime.now;

  final NotifyConfig config;
  final HttpTransport transport;
  final ProcessRunner _run;
  final SesApi Function(String region)? _ses;
  final bool _macos;

  /// `--no-notify`: nothing is sent (the stream still gets everything).
  final bool enabled;
  final Duration timeout;
  final DateTime Function() _clock;

  static final _stream = StreamController<Notification>.broadcast();

  /// Every notification of this process, sent or not.
  static Stream<Notification> get stream => _stream.stream;

  /// The channels that get [e].
  List<NotifyChannel> channelsFor(NotifyEvent e) => [
    for (final c in config.channels)
      if (c.wants(e, config.events)) c,
  ];

  /// Sends [n] everywhere it should go. Never throws.
  Future<void> send(Notification n, {EnvConfig? env, Log? log}) async {
    _stream.add(n);
    if (!enabled || !config.enabled) return;
    for (final c in channelsFor(n.event)) {
      try {
        await _deliver(c, n, env).timeout(timeout);
      } catch (x) {
        log?.warn('notification to ${c.name} failed: $x');
      }
    }
  }

  Future<void> _deliver(NotifyChannel c, Notification n, EnvConfig? env) {
    switch (c.kind) {
      case 'macos':
        return _macosNotification(n);
      case 'email':
        return _email(c, n, env);
      case 'webhook':
        return _webhook(c, n);
      case 'slack':
        return _slack(c, n);
    }
    return Future.value();
  }

  Future<void> _macosNotification(Notification n) async {
    if (!_macos) return;
    final sound = n.ok ? 'Glass' : 'Basso';
    try {
      final r = await _run('terminal-notifier', [
        '-title',
        'podship',
        '-subtitle',
        n.title,
        '-message',
        n.body.split('\n').first,
        '-group',
        'podship-${n.project ?? ''}-${n.env ?? ''}',
        '-sound',
        sound,
      ]);
      if (r.exitCode == 0) return;
    } on ProcessException {
      // terminal-notifier is not installed: osascript below.
    }
    String q(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final r = await _run('osascript', [
      '-e',
      'display notification "${q(n.body.split('\n').first)}" with title "podship" subtitle "${q(n.title)}" sound name "$sound"',
    ]);
    if (r.exitCode != 0) {
      throw Exception('osascript exited with ${r.exitCode}');
    }
  }

  Future<void> _email(NotifyChannel c, Notification n, EnvConfig? env) async {
    if (c.to.isEmpty) throw Exception('email channel ${c.name} has no "to"');
    final from = c.from ?? env?.email?.from;
    final region = c.region ?? env?.email?.region;
    if (from == null || region == null) {
      throw Exception(
        'email channel ${c.name} needs from and region (or the environment\'s email: settings)',
      );
    }
    final ses = _ses;
    if (ses == null) throw Exception('no SES client (AWS credentials)');
    await ses(region).send(
      from: from,
      to: c.to,
      subject: '[podship] ${n.title}',
      text:
          '${n.body}\n\n'
          '${n.project ?? ''}${n.env == null ? '' : '/${n.env}'}'
          '${n.host == null ? '' : ' on ${n.host}'}\n'
          '${n.time.toIso8601String()}\n',
    );
  }

  Future<void> _webhook(NotifyChannel c, Notification n) async {
    final url = c.url;
    if (url == null) throw Exception('webhook channel ${c.name} has no url');
    final body = jsonEncode(n.toJson());
    final ts = (_clock().toUtc().millisecondsSinceEpoch ~/ 1000).toString();
    final reply = await transport.send(
      HttpCall(
        'POST',
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'podship',
          'X-Podship-Event': n.event.id,
          'X-Podship-Timestamp': ts,
          if (c.secret != null)
            'X-Podship-Signature':
                'sha256=${webhookSignature(c.secret!, ts, body)}',
        },
        body: body,
      ),
    );
    if (reply.status >= 300) {
      throw Exception('webhook ${c.name} answered HTTP ${reply.status}');
    }
  }

  Future<void> _slack(NotifyChannel c, Notification n) async {
    final url = c.url;
    if (url == null) throw Exception('slack channel ${c.name} has no url');
    final reply = await transport.send(
      HttpCall(
        'POST',
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'User-Agent': 'podship'},
        body: jsonEncode({
          'text':
              '${n.ok ? ':white_check_mark:' : ':x:'} *${n.title}*\n${n.body}',
        }),
      ),
    );
    if (reply.status >= 300) {
      throw Exception('slack ${c.name} answered HTTP ${reply.status}');
    }
  }
}

/// The webhook signature: HMAC-SHA256 of `<timestamp>.<body>` with the
/// channel's secret, in hex. The receiver computes the same from the
/// `X-Podship-Timestamp` header and the raw body, and compares.
String webhookSignature(String secret, String timestamp, String body) => Hmac(
  sha256,
  utf8.encode(secret),
).convert(utf8.encode('$timestamp.$body')).toString();
