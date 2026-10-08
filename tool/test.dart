// Runs the tests and prints a short result.
//
//   dart run tool/test.dart [unit]          the unit tests (dart test -t unit)
//   dart run tool/test.dart integration     test/integration against
//       PODSHIP_IT_HOST=user@host [PODSHIP_IT_HOME=/path]; the full log
//       goes to <temp>/podship-integration.log
//
// Extra arguments go to `dart test` (for example `-n retention`). Agents
// whose hooks block `dart test` use this runner or the very_good_cli MCP
// `test` tool (dart: true, tags: unit).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final named = args.isNotEmpty && !args.first.startsWith('-');
  final tag = named ? args.first : 'unit';
  if (tag != 'unit' && tag != 'integration') {
    stderr.writeln(
      'usage: dart run tool/test.dart [unit|integration] [dart test options]',
    );
    exit(64);
  }
  final rest = named ? args.sublist(1) : args;
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final proc = await Process.start(Platform.resolvedExecutable, [
    'test',
    '-t',
    tag,
    '--reporter',
    'expanded',
    '--no-color',
    ...rest,
  ], workingDirectory: root);
  final log = File(p.join(Directory.systemTemp.path, 'podship-$tag.log'));
  final sink = log.openWrite();
  // The integration log is long: print only the podship steps and failures.
  final steps = RegExp(
    r'^(\$ podship|▶|✓|✗|!|\[[0-9]+s\]|  Expected|    Actual|  [A-Za-z].*Exception|healthy|no healthy)',
  );
  var summary = '';
  Future<void> pump(Stream<List<int>> s) =>
      s.transform(utf8.decoder).transform(const LineSplitter()).forEach((l) {
        sink.writeln(l);
        if (l.contains('All tests passed') ||
            l.contains('Some tests failed') ||
            l.contains('No tests ran')) {
          summary = l;
        }
        final show = tag == 'integration'
            ? steps.hasMatch(l)
            : l.contains('[E]') || l.startsWith('  ');
        if (show) stdout.writeln(l);
      });
  await Future.wait([pump(proc.stdout), pump(proc.stderr)]);
  final code = await proc.exitCode;
  await sink.close();
  if (summary.isNotEmpty) stdout.writeln(summary);
  stdout.writeln(
    '${code == 0 ? 'ok' : 'FAILED'}: $tag tests (exit $code); log ${log.path}',
  );
  exit(code);
}
