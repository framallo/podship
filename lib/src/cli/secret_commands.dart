// env and secret: variables and secrets that live only on the server.

import 'dart:io';

import '../edit/dotenv.dart';
import '../ops/context.dart';
import '../ops/secrets.dart';
import 'base.dart';

abstract class _EditCommand extends PodshipCommand {
  _EditCommand() {
    argParser.addFlag(
      'restart',
      negatable: false,
      help: 'Recreate the containers afterwards so the change applies.',
    );
  }
  @override
  bool get mutating => true;

  Future<int> edit(String envName, Future<int> Function() change) async {
    final code = await change();
    if (code != 0) return code;
    if (argResults!['restart'] == true) return runOp(api.restart(envName));
    if (!dryRun && !json) {
      log.info(
        'Applies at the next deploy, or now with: $exe restart --env $envName',
      );
    }
    return 0;
  }
}

class EnvSetCommand extends _EditCommand {
  @override
  String get name => 'set';
  @override
  String get description => 'Set plain (non-secret) variables: NAME=VALUE …';
  @override
  String get invocation =>
      '$exe env set NAME=VALUE [NAME=VALUE…] [--env <env>]';
  @override
  Future<int> execute() async {
    final e = env;
    final pairs = <String, String>{};
    for (final a in argResults!.rest) {
      final i = a.indexOf('=');
      if (i <= 0 || !validEnvName(a.substring(0, i))) {
        usageException('expected NAME=VALUE, got "$a"');
      }
      pairs[a.substring(0, i)] = a.substring(i + 1);
    }
    if (pairs.isEmpty) usageException('give at least one NAME=VALUE');
    return edit(e.name, () => runOp(api.envSet(e.name, pairs)));
  }
}

class EnvGetCommand extends PodshipCommand {
  @override
  String get name => 'get';
  @override
  String get description =>
      'Print a plain variable. Secrets are never printed.';
  @override
  String get invocation => '$exe env get NAME [--env <env>]';
  @override
  Future<int> execute() async {
    if (argResults!.rest.length != 1) usageException('give one NAME');
    final v = await api.envGet(env.name, argResults!.rest.single);
    json
        ? printJson({'name': argResults!.rest.single, 'value': v})
        : stdout.writeln(v);
    return 0;
  }
}

class EnvListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'Variables: plain ones with values, secrets by name only.';
  @override
  Future<int> execute() async {
    final list = await api.envList(env.name);
    if (json) {
      printJson([for (final v in list) v.toJson()]);
    } else {
      for (final v in list) {
        stdout.writeln(
          v.secret ? '${v.name} (secret)' : '${v.name}=${v.value}',
        );
      }
    }
    return 0;
  }
}

class EnvUnsetCommand extends _EditCommand {
  @override
  String get name => 'unset';
  @override
  String get description => 'Remove variables.';
  @override
  String get invocation => '$exe env unset NAME [NAME…] [--env <env>]';
  @override
  Future<int> execute() async {
    final e = env;
    if (argResults!.rest.isEmpty) usageException('give at least one NAME');
    return edit(e.name, () => runOp(api.envUnset(e.name, argResults!.rest)));
  }
}

class SecretSetCommand extends _EditCommand {
  SecretSetCommand() {
    argParser
      ..addFlag(
        'password',
        negatable: false,
        help:
            'Set a passwords.yaml key (run-mode section) instead of a .env variable.',
      )
      ..addOption('from-file', help: 'Read the value from this file.')
      ..addFlag(
        'generate',
        negatable: false,
        help: 'Use a new random value (32 bytes, base64).',
      );
  }
  @override
  String get name => 'set';
  @override
  String get description =>
      'Set a secret. The value comes from stdin, a hidden prompt, --from-file or --generate; never from arguments.';
  @override
  String get invocation =>
      '$exe secret set NAME [--password] [--from-file F | --generate] [--env <env>]';
  @override
  Future<int> execute() async {
    final e = env;
    if (argResults!.rest.length != 1) usageException('give one NAME');
    final n = argResults!.rest.single;
    final pw = argResults!['password'] == true;
    if (!pw && !validEnvName(n)) usageException('invalid name "$n"');
    final gen = argResults!['generate'] == true;
    final file = argResults!['from-file'] as String?;
    final value = dryRun
        ? ''
        : (gen || file != null || stdin.hasTerminal)
        ? readSecretValue(n, fromFile: file, generate: gen)
        : await readAllStdin();
    if (!dryRun && value.isEmpty) throw Aborted('empty value');
    return edit(
      e.name,
      () => runOp(api.secretSet(e.name, n, value, password: pw)),
    );
  }
}

class SecretListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'Secret names (never values): .env secrets and passwords.yaml keys.';
  @override
  Future<int> execute() async {
    final list = await api.secretList(env.name);
    json ? printJson(list) : list.forEach(stdout.writeln);
    return 0;
  }
}

class SecretUnsetCommand extends _EditCommand {
  SecretUnsetCommand() {
    argParser.addFlag(
      'password',
      negatable: false,
      help: 'Remove a passwords.yaml key.',
    );
  }
  @override
  String get name => 'unset';
  @override
  String get description => 'Remove secrets.';
  @override
  String get invocation =>
      '$exe secret unset NAME [NAME…] [--password] [--env <env>]';
  @override
  Future<int> execute() async {
    final e = env;
    if (argResults!.rest.isEmpty) usageException('give at least one NAME');
    return edit(
      e.name,
      () => runOp(
        api.secretUnset(
          e.name,
          argResults!.rest,
          password: argResults!['password'] == true,
        ),
      ),
    );
  }
}

class SecretCopyCommand extends _EditCommand {
  SecretCopyCommand() {
    argParser
      ..addOption(
        'from',
        mandatory: true,
        help: 'The environment to copy from.',
      )
      ..addFlag(
        'password',
        negatable: false,
        help: 'Copy passwords.yaml keys.',
      );
  }
  @override
  String get name => 'copy';
  @override
  String get description =>
      'Copy secrets from another environment. Values pass through memory only; they are never printed.';
  @override
  String get invocation =>
      '$exe secret copy --from <env> NAME [NAME…] [--env <env>]';
  @override
  Future<int> execute() async {
    final e = env;
    final from = argResults!['from'] as String;
    if (from == e.name) usageException('--from must be another environment');
    if (argResults!.rest.isEmpty) usageException('give at least one NAME');
    return edit(
      e.name,
      () => runOp(
        api.secretCopy(
          from,
          e.name,
          argResults!.rest,
          password: argResults!['password'] == true,
        ),
      ),
    );
  }
}

class SecretInitCommand extends PodshipCommand {
  SecretInitCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Replace existing files (DANGEROUS: new database password).',
    );
  }
  @override
  String get name => 'init';
  @override
  String get description =>
      'Create the .env and passwords.yaml of an environment with fresh random secrets.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final e = env;
    final force = argResults!['force'] == true;
    if (force && e.isProduction && argResults!['env'] != 'production') {
      usageException('production must be named');
    }
    return runOp(api.secretInit(e.name, force: force));
  }
}
