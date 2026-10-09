@Tags(['unit'])
library;

import 'dart:convert';

import 'package:podship/src/plan/executor.dart';
import 'package:podship/src/plan/plan.dart';
import 'package:podship/src/remote/ssh.dart';
import 'package:podship/src/server/registry.dart';
import 'package:podship/src/util/log.dart';
import 'package:test/test.dart';

import 'registry_test.dart' show entry;

/// A server whose registry another deploy changes once, between podship's
/// plan and its write.
class RacingSsh extends Ssh {
  RacingSsh(this.file, this.otherDeploy);
  String file;
  String? otherDeploy;
  final scripts = <String>[];

  @override
  Future<int> lines(
    String host,
    String script,
    void Function(String line, bool stderr) onLine,
  ) async {
    scripts.add(script);
    if (script.contains('base64 < ')) {
      onLine(base64.encode(utf8.encode(file)), false);
      return 0;
    }
    // A write attempt: the other deploy lands first, once.
    if (otherDeploy != null) {
      file = otherDeploy!;
      otherDeploy = null;
    }
    final was = utf8.decode(
      base64.decode(
        RegExp(
          r"echo '?([A-Za-z0-9+/=]*)'? \| base64 -d",
        ).firstMatch(script)![1]!,
      ),
    );
    if (was != file) return 75;
    final m = RegExp(
      r"<<'(PODSHIP_EOF\w*)'\n([\s\S]*?)\n\1\n",
    ).firstMatch(script)!;
    file = '${m[2]}\n';
    return 0;
  }
}

void main() {
  test('a registry changed by another app meanwhile is merged and written; '
      'neither deploy stops', () async {
    final base = Registry()..put(entry('a/production', ports: {'web': 20000}));
    final mine = Registry.parse(base.render())
      ..put(entry('a/production', ports: {'web': 20000}, unit: 'a-backup'));
    final theirs = Registry.parse(base.render())
      ..put(entry('b/production', ports: {'web': 20001}));
    final ssh = RacingSsh(base.render(), theirs.render());
    await Executor(ssh, Log.silent()).run(
      Plan('deploy a', [
        RegistryWriteStep(
          'Write the registry',
          'server',
          '/srv/podship/registry.yaml',
          header: '',
          base: base.render(),
          mine: mine.render(),
        ),
      ]),
    );
    final out = Registry.parse(ssh.file);
    expect(out.entries.keys, containsAll(['a/production', 'b/production']));
    expect(out.entries['a/production']!.backupUnit, 'a-backup');
    // The write holds a lock.
    expect(ssh.scripts.first, contains('registry.yaml.lock'));
  });

  test('a real clash still stops the deploy with the reason', () async {
    final base = Registry();
    final mine = Registry()..put(entry('a/production', ports: {'web': 20000}));
    final theirs = Registry()
      ..put(entry('b/production', ports: {'web': 20000}));
    final ssh = RacingSsh(base.render(), theirs.render());
    await expectLater(
      Executor(ssh, Log.silent()).run(
        Plan('deploy a', [
          RegistryWriteStep(
            'Write the registry',
            'server',
            '/srv/podship/registry.yaml',
            header: '',
            base: base.render(),
            mine: mine.render(),
          ),
        ]),
      ),
      throwsA(isA<StepError>()),
    );
  });
}
