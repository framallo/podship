import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:podship/src/cli/runner.dart';

Future<void> main(List<String> args) async {
  try {
    final code = await PodshipRunner().run(args) ?? 0;
    await Future.wait([stdout.flush(), stderr.flush()]);
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
