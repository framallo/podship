// env and secret: variables and secrets that live only on the server.

import 'dart:io';

import '../config/config.dart';
import '../edit/dotenv.dart';
import '../edit/passwords.dart';
import '../ops/context.dart';
import '../ops/release_ops.dart';
import '../ops/secrets.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
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

  Future<int> runEdit(EnvConfig e, Plan plan) async {
    await ctx.run(plan);
    if (argResults!['restart'] == true) {
      final (:state, :r) = await load(e);
      await ctx.run(planRestart(ctx: ctx, r: r, state: state));
    } else if (!dryRun) {
      log.info(
        'Applies at the next deploy, or now with: $exe restart --env ${e.name}',
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
      if (i <= 0 || !validEnvName(a.substring(0, i)))
        usageException('expected NAME=VALUE, got "$a"');
      pairs[a.substring(0, i)] = a.substring(i + 1);
    }
    if (pairs.isEmpty) usageException('give at least one NAME=VALUE');
    final l = EnvLayout(e);
    return runEdit(
      e,
      Plan('env set on ${e.name}', [
        ActionStep(
          'Edit ${l.envFile}',
          'set ${pairs.entries.map((x) => '${x.key}=${x.value}').join(' ')} (plain)',
          () async {
            final f = DotEnv(await readRemote(ctx, e, l.envFile));
            pairs.forEach((k, v) => f.set(k, v, plain: true));
            await writeRemote(ctx, e, l.envFile, f.toString());
          },
        ),
      ]),
    );
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
    final e = env;
    if (argResults!.rest.length != 1) usageException('give one NAME');
    final n = argResults!.rest.single;
    final f = DotEnv(await readRemote(ctx, e, EnvLayout(e).envFile));
    if (!f.has(n)) throw Aborted('$n is not set in ${e.name}');
    if (!isPlain(e, f, n))
      throw Aborted('$n is a secret; podship never prints secret values');
    stdout.writeln(f.get(n));
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
    final e = env;
    final f = DotEnv(await readRemote(ctx, e, EnvLayout(e).envFile));
    listLines(e, f, secretsOnly: false).forEach(stdout.writeln);
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
    final names = argResults!.rest;
    if (names.isEmpty) usageException('give at least one NAME');
    final l = EnvLayout(e);
    return runEdit(
      e,
      Plan('env unset on ${e.name}', [
        editRemote(ctx, e, l.envFile, 'unset ${names.join(' ')}', (t) {
          final f = DotEnv(t);
          names.forEach(f.unset);
          return f.toString();
        }),
      ]),
    );
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
    final value = dryRun
        ? ''
        : (argResults!['generate'] == true ||
              argResults!['from-file'] != null ||
              stdin.hasTerminal)
        ? readSecretValue(
            n,
            fromFile: argResults!['from-file'] as String?,
            generate: argResults!['generate'] == true,
          )
        : await readAllStdin();
    if (!dryRun && value.isEmpty) throw Aborted('empty value');
    final l = EnvLayout(e);
    final path = pw ? l.passwordsFile : l.envFile;
    return runEdit(
      e,
      Plan('secret set on ${e.name}', [
        editRemote(ctx, e, path, 'set ${pw ? '${e.runMode}.' : ''}$n', (t) {
          if (pw) {
            final f = PasswordsFile(t)..set(e.runMode, n, value);
            return f.toString();
          }
          final f = DotEnv(t)..set(n, value);
          return f.toString();
        }),
      ]),
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
    final e = env;
    final l = EnvLayout(e);
    final f = DotEnv(await readRemote(ctx, e, l.envFile));
    for (final n in f.names) {
      if (!isPlain(e, f, n)) stdout.writeln(n);
    }
    final pw = PasswordsFile(await readRemote(ctx, e, l.passwordsFile));
    for (final s in pw.sections) {
      for (final k in pw.keys(s)) {
        stdout.writeln('password $s.$k');
      }
    }
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
    final names = argResults!.rest;
    if (names.isEmpty) usageException('give at least one NAME');
    final pw = argResults!['password'] == true;
    final l = EnvLayout(e);
    return runEdit(
      e,
      Plan('secret unset on ${e.name}', [
        editRemote(
          ctx,
          e,
          pw ? l.passwordsFile : l.envFile,
          'unset ${names.join(' ')}',
          (t) {
            if (pw) {
              final f = PasswordsFile(t);
              for (final n in names) {
                f.unset(e.runMode, n);
              }
              return f.toString();
            }
            final f = DotEnv(t);
            names.forEach(f.unset);
            return f.toString();
          },
        ),
      ]),
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
    final src = config.env(argResults!['from'] as String);
    if (src.name == e.name)
      usageException('--from must be another environment');
    final names = argResults!.rest;
    if (names.isEmpty) usageException('give at least one NAME');
    final pw = argResults!['password'] == true;
    final sl = EnvLayout(src), dl = EnvLayout(e);
    return runEdit(
      e,
      Plan('secret copy ${src.name} → ${e.name}', [
        ActionStep(
          'Copy ${names.join(', ')}',
          '${src.name} → ${e.name} (values hidden)',
          () async {
            if (pw) {
              final from = PasswordsFile(
                await readRemote(ctx, src, sl.passwordsFile),
              );
              final to = PasswordsFile(
                await readRemote(ctx, e, dl.passwordsFile),
              );
              for (final n in names) {
                final v = from.get(src.runMode, n) ?? from.get('shared', n);
                if (v == null) throw Aborted('${src.name} has no password $n');
                to.set(e.runMode, n, v);
              }
              await writeRemote(ctx, e, dl.passwordsFile, to.toString());
            } else {
              final from = DotEnv(await readRemote(ctx, src, sl.envFile));
              final to = DotEnv(await readRemote(ctx, e, dl.envFile));
              for (final n in names) {
                final v = from.get(n);
                if (v == null) throw Aborted('${src.name} has no $n');
                to.set(n, v);
              }
              await writeRemote(ctx, e, dl.envFile, to.toString());
            }
          },
        ),
      ]),
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
    if (argResults!['force'] == true &&
        e.isProduction &&
        argResults!['env'] != 'production') {
      usageException('production must be named');
    }
    await ctx.run(planSecretInit(ctx, e, force: argResults!['force'] == true));
    return 0;
  }
}
