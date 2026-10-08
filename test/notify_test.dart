import 'dart:convert';
import 'dart:io';

import 'package:podship/podship.dart';
import 'package:podship/src/cli/base.dart' show summaryLine;
import 'package:test/test.dart';

import 'fixtures.dart';

/// Replays the events of a deploy through a watcher.
List<Notification> replay(List<PodshipEvent> events) {
  final w = OperationWatcher();
  return [for (final e in events) ...w.onEvent(e)];
}

OperationResult result({
  required bool ok,
  String operation = 'deploy',
  String? release,
  String? previous,
  String? error,
  bool dryRun = false,
}) => OperationResult(
  operation: operation,
  ok: ok,
  duration: const Duration(seconds: 90),
  project: 'demo',
  env: 'staging',
  host: 'prod-box',
  release: release,
  previousRelease: previous,
  error: error,
  dryRun: dryRun,
);

void main() {
  group('OperationWatcher', () {
    test(
      'a deploy announces its start and its end, with health and stages',
      () {
        final ns = replay([
          OperationStarted(
            'deploy',
            project: 'demo',
            env: 'staging',
            host: 'prod-box',
          ),
          StepStarted(1, 3, 'Run tests (server)'),
          StepFinished(1, 'Run tests (server)', const Duration(seconds: 48)),
          StepStarted(2, 3, 'Build images on the server'),
          StepFinished(
            2,
            'Build images on the server',
            const Duration(seconds: 130),
          ),
          StepStarted(3, 3, 'Health check'),
          StepFinished(3, 'Health check', const Duration(seconds: 7)),
          OperationFinished(result(ok: true, release: 'r2', previous: 'r1')),
        ]);
        expect(ns.map((n) => n.event), [
          NotifyEvent.deployStarted,
          NotifyEvent.deployDone,
        ]);
        final done = ns.last;
        expect(done.ok, isTrue);
        expect(done.release, 'r2');
        expect(done.title, 'deploy done (demo/staging): r2');
        expect(done.body, contains('health: ok'));
        expect(done.body, contains('build 130.0 s'));
        expect(done.data['healthy'], isTrue);
        final stages = done.data['stages'] as List;
        expect(stages, hasLength(3));
        expect((stages[1] as Map)['duration_ms'], 130000);
      },
    );

    test('a failed deploy carries the automatic rollback result', () {
      final ns = replay([
        OperationStarted('deploy', project: 'demo', env: 'staging'),
        StepStarted(5, 6, 'Switch to r2'),
        StepFinished(5, 'Switch to r2', const Duration(seconds: 8)),
        StepStarted(6, 6, 'Health check'),
        StepFailed(6, 'Health check', 'not healthy'),
        StepStarted(1, 3, 'Mark r2 failed', recovery: true),
        StepFinished(1, 'Mark r2 failed', Duration.zero),
        StepStarted(2, 3, 'Roll back to r1', recovery: true),
        StepFinished(2, 'Roll back to r1', const Duration(seconds: 9)),
        StepStarted(3, 3, 'Health check of r1', recovery: true),
        StepFinished(3, 'Health check of r1', const Duration(seconds: 6)),
        OperationFinished(
          result(
            ok: false,
            release: 'r1',
            previous: 'r1',
            error: 'Health check: not healthy',
          ),
        ),
      ]);
      expect(ns.map((n) => n.event), [
        NotifyEvent.deployStarted,
        NotifyEvent.deployFailed,
      ]);
      final failed = ns.last;
      expect(failed.ok, isFalse);
      expect(failed.body, contains('rolled back to r1: healthy'));
      expect(failed.data['rollback'], 'ok');
      expect(failed.data['rollback_to'], 'r1');
      final stages = (failed.data['stages'] as List).cast<Map>();
      expect(stages.where((s) => s['recovery'] == true), hasLength(3));
      expect(stages.where((s) => s['ok'] == false), hasLength(1));
    });

    test('a failed rollback step is reported as such', () {
      final ns = replay([
        OperationStarted('deploy', project: 'demo', env: 'staging'),
        StepStarted(6, 6, 'Health check'),
        StepFailed(6, 'Health check', 'not healthy'),
        StepStarted(2, 3, 'Roll back to r1', recovery: true),
        StepFailed(2, 'Roll back to r1', 'exit code 1'),
        OperationFinished(result(ok: false, release: 'r2', error: 'x')),
      ]);
      expect(ns.last.data['rollback'], 'failed');
      expect(ns.last.body, contains('rollback to r1 FAILED'));
    });

    test('a failure before the switch says no rollback happened', () {
      final ns = replay([
        OperationStarted('deploy', project: 'demo', env: 'staging'),
        StepStarted(2, 6, 'Run tests (server)'),
        StepFailed(2, 'Run tests (server)', 'tests failed'),
        OperationFinished(result(ok: false, release: 'r1', error: 'tests')),
      ]);
      expect(ns.last.data['rollback'], 'none');
    });

    test('rollback done, backup failed; dry runs and reads are silent', () {
      expect(
        replay([
          OperationStarted('rollback', project: 'demo', env: 'staging'),
          OperationFinished(
            result(operation: 'rollback', ok: true, release: 'r1'),
          ),
        ]).single.event,
        NotifyEvent.rollbackDone,
      );
      expect(
        replay([
          OperationStarted('backup now', project: 'demo', env: 'staging'),
          OperationFinished(
            result(operation: 'backup now', ok: false, error: 'pg_dump'),
          ),
        ]).single.event,
        NotifyEvent.backupFailed,
      );
      expect(
        replay([
          OperationStarted('backup now', project: 'demo', env: 'staging'),
          OperationFinished(result(operation: 'backup now', ok: true)),
        ]),
        isEmpty,
      );
      expect(
        replay([
          OperationStarted('deploy', project: 'demo', dryRun: true),
          OperationFinished(result(ok: true, dryRun: true)),
        ]),
        isEmpty,
      );
      expect(
        replay([
          OperationStarted('env set', project: 'demo', env: 'staging'),
          OperationFinished(result(operation: 'env set', ok: true)),
        ]),
        isEmpty,
      );
    });

    test('the scheduler can build its own notification', () {
      final n = Notification.schedulerJobFailed(
        job: 'backup demo/production',
        error: 'disk full',
        project: 'demo',
        env: 'production',
      );
      expect(n.event, NotifyEvent.schedulerJobFailed);
      expect(n.toJson()['event'], 'scheduler_job_failed');
      expect(n.ok, isFalse);
    });
  });

  group('summary line', () {
    test('names the outcome, the release, the time and the slow stages', () {
      final line = summaryLine(result(ok: true, release: 'r2'), [
        StageTiming('Run tests (server)', const Duration(seconds: 48)),
        StageTiming('Build images on the server', const Duration(seconds: 130)),
        StageTiming('Upload files', const Duration(seconds: 1)),
      ]);
      expect(
        line,
        'deploy staging ok: r2 in 90.0 s (build 130.0 s, tests 48.0 s)',
      );
    });
  });

  group('NotifyConfig', () {
    test('parses events and channels; the project wins over the global', () {
      final global = PodshipConfig.parse(
        '$sampleConfig\n'
        'notify:\n'
        '  events: [deploy_done]\n'
        '  channels:\n'
        '    macos: {}\n'
        '    slack: {url: https://hooks.example/global}\n'
        '    hook: {kind: webhook, url: https://hooks.example/w, secret: topsecret}\n',
        environment: const {},
      ).notify;
      expect(global.events, [NotifyEvent.deployDone]);
      expect(global.channel('hook')!.kind, 'webhook');
      expect(global.channel('hook')!.secret, 'topsecret');

      final project = PodshipConfig.parse(
        '$sampleConfig\n'
        'notify:\n'
        '  channels:\n'
        '    slack: {url: https://hooks.example/project, events: [deploy_failed]}\n'
        '    mail: {kind: email, to: [ops@example.com]}\n',
        globalNotify: global,
        environment: const {'PODSHIP_WEBHOOK_SECRET': 'fromenv'},
      ).notify;
      // No events in the project file: the global list stays.
      expect(project.events, [NotifyEvent.deployDone]);
      expect(project.channel('slack')!.url, 'https://hooks.example/project');
      expect(project.channel('slack')!.events, [NotifyEvent.deployFailed]);
      expect(project.channel('macos'), isNotNull);
      expect(project.channel('mail')!.to, ['ops@example.com']);
      expect(project.channel('hook')!.secret, 'topsecret');
      expect(project.channels, hasLength(4));
    });

    test('rejects unknown events and kinds', () {
      expect(
        () => PodshipConfig.parse(
          '$sampleConfig\nnotify: {events: [deploy_exploded]}\n',
          environment: const {},
        ),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => PodshipConfig.parse(
          '$sampleConfig\nnotify: {channels: {pager: {url: x}}}\n',
          environment: const {},
        ),
        throwsA(isA<ConfigException>()),
      );
    });

    test('the webhook secret and URLs come from the environment too', () {
      final c = PodshipConfig.parse(
        '$sampleConfig\n'
        'notify:\n'
        '  channels:\n'
        '    hook: {kind: webhook, url_env: HOOK_URL, secret_env: HOOK_SECRET}\n',
        environment: const {
          'HOOK_URL': 'https://hooks.example/x',
          'HOOK_SECRET': 's3',
        },
      ).notify;
      expect(c.channel('hook')!.url, 'https://hooks.example/x');
      expect(c.channel('hook')!.secret, 's3');
    });
  });

  group('Notifier', () {
    final n = Notification(
      event: NotifyEvent.deployDone,
      title: 'deploy done (demo/staging): r2',
      body: 'release r2\ntook 90.0 s\nhealth: ok',
      ok: true,
      project: 'demo',
      env: 'staging',
      release: 'r2',
      duration: const Duration(seconds: 90),
      time: DateTime.utc(2026, 10, 8, 2, 0, 0),
    );

    test('webhook: JSON POST with event, timestamp and HMAC headers', () async {
      final t = FixtureTransport([
        Fixture('POST', '/hook', jsonReply({'ok': true})),
      ]);
      final notifier = Notifier(
        NotifyConfig(
          channels: [
            NotifyChannel(
              name: 'hook',
              kind: 'webhook',
              url: 'https://hooks.example/hook',
              secret: 'topsecret',
            ),
          ],
        ),
        transport: t,
        macos: false,
        clock: () => DateTime.utc(2026, 10, 8, 2, 0, 1),
      );
      await notifier.send(n);
      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.headers['X-Podship-Event'], 'deploy_done');
      expect(call.headers['X-Podship-Timestamp'], '1791424801');
      final body = call.body!;
      expect(
        call.headers['X-Podship-Signature'],
        'sha256=${webhookSignature('topsecret', '1791424801', body)}',
      );
      final j = jsonDecode(body) as Map;
      expect(j['event'], 'deploy_done');
      expect(j['release'], 'r2');
      expect(j['duration_ms'], 90000);
      expect(body, isNot(contains('topsecret')));
    });

    test('the signature has a fixed value for a known input', () {
      expect(
        webhookSignature('key', '1700000000', '{"a":1}'),
        'a438e398bfafc57e4396bb7fc2304422f0f768e965d073ca313cb52e22e6ad03',
      );
    });

    test(
      'slack: a text payload; a failing channel is a warning only',
      () async {
        final t = FixtureTransport([
          Fixture('POST', '/services/T/B/x', jsonReply('ok')),
          Fixture('POST', '/down', jsonReply({'error': 'x'}, status: 500)),
        ]);
        final warnings = <String>[];
        final log = Log((e) {
          if (e is LogLine && e.level == LogLevel.warn) warnings.add(e.text);
        });
        final notifier = Notifier(
          NotifyConfig(
            channels: [
              NotifyChannel(
                name: 'slack',
                kind: 'slack',
                url: 'https://hooks.slack.com/services/T/B/x',
              ),
              NotifyChannel(
                name: 'dead',
                kind: 'webhook',
                url: 'https://hooks.example/down',
              ),
            ],
          ),
          transport: t,
          macos: false,
        );
        await notifier.send(n, log: log);
        expect(t.calls, hasLength(2));
        final slack = jsonDecode(t.calls.first.body!) as Map;
        expect(slack['text'], contains('deploy done (demo/staging): r2'));
        expect(warnings.single, contains('dead'));
        expect(warnings.single, contains('500'));
      },
    );

    test('channels get only the events they want', () async {
      final t = FixtureTransport([
        Fixture('POST', '/a', jsonReply('ok'), times: 5),
        Fixture('POST', '/b', jsonReply('ok'), times: 5),
      ]);
      final notifier = Notifier(
        NotifyConfig(
          events: [NotifyEvent.deployFailed],
          channels: [
            NotifyChannel(name: 'a', kind: 'slack', url: 'https://h/a'),
            NotifyChannel(
              name: 'b',
              kind: 'slack',
              url: 'https://h/b',
              events: [NotifyEvent.deployDone],
            ),
          ],
        ),
        transport: t,
        macos: false,
      );
      await notifier.send(n);
      expect(t.calls.map((c) => c.url.path), ['/b']);
    });

    test(
      'macOS: terminal-notifier first, osascript when it is missing',
      () async {
        final runs = <List<String>>[];
        var hasTerminalNotifier = false;
        Future<ProcessResult> run(String exe, List<String> args) async {
          runs.add([exe, ...args]);
          if (exe == 'terminal-notifier' && !hasTerminalNotifier) {
            throw ProcessException(exe, args, 'not found', 2);
          }
          return ProcessResult(0, 0, '', '');
        }

        final cfg = NotifyConfig(
          channels: [NotifyChannel(name: 'macos', kind: 'macos')],
        );
        await Notifier(cfg, run: run, macos: true).send(n);
        expect(runs.map((r) => r.first), ['terminal-notifier', 'osascript']);
        expect(runs.last[2], contains('display notification "release r2"'));
        runs.clear();
        hasTerminalNotifier = true;
        await Notifier(cfg, run: run, macos: true).send(n);
        expect(runs.single.first, 'terminal-notifier');
        expect(runs.single, contains('-subtitle'));
        // Not on macOS: nothing runs.
        runs.clear();
        await Notifier(cfg, run: run, macos: false).send(n);
        expect(runs, isEmpty);
      },
    );

    test('email goes through SES with the environment sender', () async {
      final t = FixtureTransport([
        Fixture(
          'POST',
          '/v2/email/outbound-emails',
          jsonReply({'MessageId': 'm1'}),
        ),
      ]);
      final config = PodshipConfig.parse(
        '$sampleConfig\n'
        'notify:\n'
        '  channels:\n'
        '    mail: {kind: email, to: [ops@example.com]}\n',
        environment: const {},
      );
      final env = PodshipConfig.parse(
        sampleConfig.replaceFirst(
          '    plain_env: [PORT_WEB]\n',
          '    plain_env: [PORT_WEB]\n'
              '    email: {from: "Demo <hola@demo.example.com>", region: us-west-1}\n',
        ),
      ).env('production');
      final notifier = Notifier(
        config.notify,
        ses: (region) => SesApi(
          AwsCredentials('AKIA', 'secret'),
          region: region,
          transport: t,
        ),
        macos: false,
      );
      await notifier.send(n, env: env);
      final j = jsonDecode(t.calls.single.body!) as Map;
      expect(j['FromEmailAddress'], 'Demo <hola@demo.example.com>');
      expect((j['Destination'] as Map)['ToAddresses'], ['ops@example.com']);
      expect(((j['Content'] as Map)['Simple'] as Map)['Subject'], {
        'Data': '[podship] deploy done (demo/staging): r2',
        'Charset': 'UTF-8',
      });
      expect(t.calls.single.url.host, 'email.us-west-1.amazonaws.com');
    });

    test('--no-notify sends nothing but still feeds the stream', () async {
      final t = FixtureTransport();
      final notifier = Notifier(
        NotifyConfig(
          channels: [
            NotifyChannel(name: 's', kind: 'slack', url: 'https://h/s'),
          ],
        ),
        transport: t,
        macos: false,
        enabled: false,
      );
      final seen = Notifier.stream.first;
      await notifier.send(n);
      expect(t.calls, isEmpty);
      expect((await seen).release, 'r2');
    });
  });

  group('protocol', () {
    test('last_deploy and subscribe_events are in the catalog', () {
      expect(operationSpec('last_deploy')!.mutating, isFalse);
      final sub = operationSpec('subscribe_events')!;
      expect(sub.needsEnv, isFalse);
      expect(
        (sub.inputSchema()['properties'] as Map)['events'],
        containsPair('type', 'array'),
      );
      expect(
        (operationSpec('deploy')!.inputSchema()['properties'] as Map).keys,
        contains('full_tests'),
      );
    });
  });
}
