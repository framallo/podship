@Tags(['unit'])
library;

import 'package:podship/src/config/config.dart';
import 'package:podship/src/ops/context.dart';
import 'package:podship/src/ops/deploy.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:podship/src/ops/state.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/server/registry.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

String _withScheduled() => sampleConfig.replaceFirst(
  '      public_url: https://demo.example.com/health\n',
  '      public_url: https://demo.example.com/health\n'
      '    scheduled:\n'
      '      - {name: shots, cwd: tool, run: [dart, run, bin/tool.dart, shots, --all]}\n',
);

void main() {
  group('scheduled: commands', () {
    test('parse: name, argv and the release folder', () {
      final c = PodshipConfig.parse(_withScheduled(), root: '/work/demo');
      final s = c.env('production').scheduled.single;
      expect(s.name, 'shots');
      expect(s.run, ['dart', 'run', 'bin/tool.dart', 'shots', '--all']);
      expect(s.cwd, 'tool');
      expect(c.env('staging').scheduled, isEmpty);
    });

    test('a command job round-trips the registry and runs after backups '
        'and pulls', () {
      final reg = Registry()
        ..putJob(
          ScheduledJob(
            kind: JobKind.command,
            project: 'demo',
            env: 'production',
            name: 'shots',
            run: ['dart', 'run', 'x'],
            cwd: '/srv/demo/current/tool',
          ),
        )
        ..putJob(
          ScheduledJob(
            kind: JobKind.backup,
            project: 'demo',
            env: 'production',
            conf: '/c',
          ),
        );
      final back = Registry.parse(reg.render());
      final job = back.jobs['command:demo/production/shots']!;
      expect(job.run, ['dart', 'run', 'x']);
      expect(job.cwd, '/srv/demo/current/tool');
      expect(back.orderedJobs.map((j) => j.kind), [
        JobKind.backup,
        JobKind.command,
      ]);
    });

    test('a deploy writes the commands into the registry of its server', () {
      final config = PodshipConfig.parse(_withScheduled(), root: '/work/demo');
      final ctx = Ctx(
        config: config,
        ssh: Ssh(),
        log: Log.silent(),
        dryRun: true,
      );
      final s = parseState(
        'CURRENT \nENVFILE yes\nDB yes\nPORTS 22\nREGISTRY-BEGIN\nREGISTRY-END\n',
      );
      final r = resolveEnv(
        config,
        config.env('production'),
        s.registry,
        listening: s.listening,
      );
      final plan = planDeploy(
        ctx: ctx,
        r: r,
        state: s,
        git: GitInfo('a0dc2b0123456789', ref: 'main'),
        now: DateTime.utc(2026, 10, 8),
        snapshot: '/tmp/snap',
      );
      // The registry is written under its lock, merged with the file on
      // the server (RegistryWriteStep), not in the prepare script.
      final write = plan.steps.whereType<RegistryWriteStep>().single;
      expect(write.mine, contains('command:demo/production/shots'));
      expect(write.mine, contains('/srv/demo/current/tool'));
    });
  });
}
