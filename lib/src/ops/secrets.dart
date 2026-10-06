// env, secret: variables and secrets that live only on the server.
//
// podship reads the remote file over ssh into memory, changes it, and writes
// it back over ssh stdin with mode 0600. Values never appear in arguments,
// in the log or in plans.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../edit/dotenv.dart';
import '../edit/passwords.dart';
import '../plan/plan.dart';
import '../release/layout.dart';
import '../remote/ssh.dart';
import 'context.dart';

/// A random secret: [bytes] random bytes in base64 without padding.
String randomSecret([int bytes = 32]) {
  final r = Random.secure();
  return base64
      .encode(List.generate(bytes, (_) => r.nextInt(256)))
      .replaceAll('=', '');
}

/// Reads a remote file. A missing file is empty text.
Future<String> readRemote(Ctx ctx, EnvConfig env, String path) =>
    ctx.query(env, 'cat ${shq(path)} 2>/dev/null || true');

/// Writes a remote file from stdin with mode 0600.
Future<void> writeRemote(
  Ctx ctx,
  EnvConfig env,
  String path,
  String text,
) => ctx.query(
  env,
  'umask 077; mkdir -p ${shq(p.posix.dirname(path))}; '
  'cat > ${shq('$path.podship-tmp')} && chmod 600 ${shq('$path.podship-tmp')} && '
  'mv -f ${shq('$path.podship-tmp')} ${shq(path)}',
  stdin: utf8.encode(text),
);

/// A step that edits a remote file in memory. The description never shows
/// values.
ActionStep editRemote(
  Ctx ctx,
  EnvConfig env,
  String path,
  String what,
  String Function(String) change,
) => ActionStep('Edit $path', '$what (value hidden)', () async {
  final before = await readRemote(ctx, env, path);
  final after = change(before);
  if (after != before) await writeRemote(ctx, env, path, after);
});

/// Whether [name] is plain (printable) in [env].
bool isPlain(EnvConfig env, DotEnv f, String name) =>
    env.plainEnv.contains(name) || f.markedPlain(name);

/// `env list` / `secret list` output lines.
List<String> listLines(EnvConfig env, DotEnv f, {required bool secretsOnly}) {
  final out = <String>[];
  for (final n in f.names) {
    final plain = isPlain(env, f, n);
    if (secretsOnly && plain) continue;
    out.add(plain ? '$n=${f.get(n)}' : '$n (secret)');
  }
  return out;
}

/// The local `passwords.yaml` key names (never values) that `secret init`
/// generates fresh values for.
List<String> passwordKeysFor(PodshipConfig config, EnvConfig env) {
  if (env.secrets.passwordKeys.isNotEmpty) return env.secrets.passwordKeys;
  final keys = <String>{'database', 'serviceSecret'};
  final local = File(
    p.join(config.root, config.serverPackage, 'config', 'passwords.yaml'),
  );
  if (local.existsSync()) {
    final f = PasswordsFile(local.readAsStringSync());
    for (final s in f.sections) {
      if (s == 'shared' || s == env.runMode || s == 'development') {
        keys.addAll(f.keys(s));
      }
    }
  }
  // Development-only keys have no place on a server.
  keys.remove('redis');
  return keys.toList()..sort();
}

/// Plans `secret init`: create the env's `.env` and `passwords.yaml` with
/// fresh random values. Existing files are left alone unless [force].
Plan planSecretInit(Ctx ctx, EnvConfig env, {bool force = false}) {
  final l = EnvLayout(env);
  final keys = passwordKeysFor(ctx.config, env);
  final template = env.secrets.template == null
      ? null
      : File(p.join(ctx.config.root, env.secrets.template!));
  if (template != null && !template.existsSync()) {
    throw ConfigException('secrets.template ${env.secrets.template} not found');
  }
  return Plan('secret init for ${env.name} on ${env.host}', [
    ActionStep(
      'Create ${l.passwordsFile}',
      'section ${env.runMode}: ${keys.join(', ')} = fresh random values',
      () async {
        final before = await readRemote(ctx, env, l.passwordsFile);
        if (before.trim().isNotEmpty && !force) {
          ctx.log.info(
            '${l.passwordsFile} exists; kept (use --force to replace)',
          );
          return;
        }
        final f = PasswordsFile(
          '# Serverpod passwords for ${env.name}. Written by podship.\n',
        );
        for (final k in keys) {
          f.set(env.runMode, k, randomSecret());
        }
        await writeRemote(ctx, env, l.passwordsFile, f.toString());
      },
    ),
    ActionStep(
      'Create ${l.envFile}',
      '${template == null ? 'empty file' : 'from ${env.secrets.template}'}'
          '${env.secrets.generate.isEmpty ? '' : '; random ${env.secrets.generate.join(', ')}'}'
          '${env.secrets.databasePasswordEnv == null ? '' : '; ${env.secrets.databasePasswordEnv} = passwords database'}',
      () async {
        final before = await readRemote(ctx, env, l.envFile);
        if (before.trim().isNotEmpty && !force) {
          ctx.log.info('${l.envFile} exists; kept (use --force to replace)');
          return;
        }
        final f = DotEnv(template?.readAsStringSync() ?? '');
        // Template values are examples; drop the ones that look secret.
        for (final n in env.secrets.generate) {
          f.set(
            n,
            base64.encode(
              List.generate(32, (_) => Random.secure().nextInt(256)),
            ),
          );
        }
        final dbEnv = env.secrets.databasePasswordEnv;
        if (dbEnv != null) {
          final pw = PasswordsFile(await readRemote(ctx, env, l.passwordsFile));
          final db = pw.get(env.runMode, 'database');
          if (db != null) f.set(dbEnv, db);
        }
        await writeRemote(ctx, env, l.envFile, f.toString());
      },
    ),
  ]);
}

/// Reads a secret value: from a file, from piped stdin, or from a hidden
/// prompt. Never from arguments.
String readSecretValue(String name, {String? fromFile, bool generate = false}) {
  if (generate) return randomSecret();
  if (fromFile != null) {
    return File(fromFile).readAsStringSync().replaceAll(RegExp(r'\n$'), '');
  }
  stdout.write('Value for $name (hidden): ');
  stdin.echoMode = false;
  try {
    return stdin.readLineSync(encoding: utf8) ?? '';
  } finally {
    stdin.echoMode = true;
    stdout.writeln();
  }
}

/// Reads all of stdin (for piped secret values).
Future<String> readAllStdin() async {
  final bytes = await stdin.fold<List<int>>([], (a, b) => a..addAll(b));
  return utf8.decode(bytes).replaceAll(RegExp(r'\n$'), '');
}
