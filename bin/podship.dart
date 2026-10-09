import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:podship/src/cli/runner.dart';
import 'package:podship/src/integrations/console_secrets.dart';

/// Commands that use Cloudflare or AWS: they read the workspace's
/// integrations from the podship console first (no Keychain login).
const _providerCommands = <String, Set<String>>{
  'email': {'aws', 'cloudflare'},
  'app': {'aws', 'cloudflare'},
  'provider': {'aws', 'cloudflare'},
  'dns': {'cloudflare'},
  'tunnel': {'cloudflare'},
  'domain': {'cloudflare'},
  'status': {'cloudflare'},
};

Future<void> main(List<String> args) async {
  if (args.isNotEmpty &&
      _providerCommands.containsKey(args.first) &&
      !args.contains('--help') &&
      !args.contains('-h')) {
    await ConsoleCredentials.prime(
      providers: _providerCommands[args.first]!,
      warn: (m) => stderr.writeln('podship console: $m; using the Keychain'),
    );
  }
  try {
    final code = await PodshipRunner().run(args) ?? 0;
    await Future.wait([stdout.flush(), stderr.flush()]);
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
