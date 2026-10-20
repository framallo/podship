// REV-19 (podship#3): the release gate skips when its inputs passed before,
// like a suite.
@Tags(['unit'])
library;

import 'package:podship/podship.dart';
import 'package:podship/src/images/images.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const _gate =
    '$sampleConfig\n'
    'tests:\n'
    '  gate:\n'
    '    environments: [production]\n'
    '    image:\n'
    '      dir: demo_tool\n'
    '      command: dart run bin/tool.dart gate\n'
    '      inputs: [demo_flutter/integration_test, demo_tool/fixtures]\n'
    '      seed: dart run bin/tool.dart seed\n';

void main() {
  group('tests.gate.image by hash', () {
    test('inputs and skip_unchanged are read; skip_unchanged is on', () {
      final g = PodshipConfig.parse(_gate).tests.imageGate!;
      expect(g.inputs, ['demo_flutter/integration_test', 'demo_tool/fixtures']);
      expect(g.skipUnchanged, isTrue);
      final off = PodshipConfig.parse(
        '$_gate      skip_unchanged: false\n',
      ).tests.imageGate!;
      expect(off.skipUnchanged, isFalse);
    });

    test('the salt names everything the gate depends on besides the files', () {
      final g = PodshipConfig.parse(_gate).tests.imageGate!;
      final a = gateSalt(
        g,
        imageKey: 'img-1',
        platform: 'linux/arm64',
        tools: const ['flutter 3.38.1+abc', 'dart 3.13.2'],
      );
      expect(a, contains('command=dart run bin/tool.dart gate'));
      expect(a, contains('seed=dart run bin/tool.dart seed'));
      expect(a, contains('image=img-1'));
      expect(a, contains('platform=linux/arm64'));
      expect(a, contains('flutter 3.38.1+abc'));
      expect(a.where((s) => s.startsWith('server=')), hasLength(1));
      // The same inputs give the same salt; a changed image key does not.
      expect(
        gateSalt(
          g,
          imageKey: 'img-1',
          platform: 'linux/arm64',
          tools: const ['flutter 3.38.1+abc', 'dart 3.13.2'],
        ),
        a,
      );
      expect(
        gateSalt(
          g,
          imageKey: 'img-2',
          platform: 'linux/arm64',
          tools: const ['flutter 3.38.1+abc', 'dart 3.13.2'],
        ),
        isNot(a),
      );
    });

    test('the image report says when the gate was skipped as unchanged', () {
      final r = ImageReport()
        ..gate = 'unchanged'
        ..gateSameAs = 'a0dc2b0';
      expect(r.toJson()['gate'], 'unchanged');
      expect(r.toJson()['gate_same_as'], 'a0dc2b0');
    });
  });
}
