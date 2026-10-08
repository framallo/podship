import 'dart:io';

import 'package:podship/src/agent/proc.dart';
import 'package:test/test.dart';

void main() {
  test('a reader that stops early is no error: the exit code decides '
      '(pg_restore --list reads only the table of contents)', () async {
    final dir = Directory.systemTemp.createTempSync('podship_proc_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File('${dir.path}/dump')
      ..writeAsBytesSync(List<int>.filled(4 * 1024 * 1024, 65));
    final r = await SystemProc().run(['head', '-c', '10'], stdinFile: big.path);
    expect(r.ok, isTrue);
    expect(r.stdout, 'AAAAAAAAAA');
  });

  test('a failing reader still fails by its exit code', () async {
    final dir = Directory.systemTemp.createTempSync('podship_proc_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final big = File('${dir.path}/dump')
      ..writeAsBytesSync(List<int>.filled(4 * 1024 * 1024, 65));
    final r = await SystemProc().run([
      'sh',
      '-c',
      'head -c 1 >/dev/null; exit 3',
    ], stdinFile: big.path);
    expect(r.code, 3);
  });

  test('isBrokenPipe knows EPIPE and nothing else', () {
    expect(
      isBrokenPipe(
        const SocketException(
          'Write failed',
          osError: OSError('Broken pipe', 32),
        ),
      ),
      isTrue,
    );
    expect(isBrokenPipe(const FileSystemException('no such file')), isFalse);
    expect(isBrokenPipe(StateError('x')), isFalse);
  });
}
