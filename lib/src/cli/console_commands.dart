// login, logout, whoami, operations: the console side of the CLI.

import 'dart:convert' show utf8;
import 'dart:io';

import '../ops/context.dart';
import '../protocol/protocol.dart';
import '../protocol/tokens.dart';
import '../protocol/transport.dart';
import 'base.dart';

class LoginCommand extends PodshipCommand {
  @override
  String get name => 'login';
  @override
  String get description =>
      'Store a personal access token for a podship console (create it in the console). The token is read from stdin or a hidden prompt.';
  @override
  String get invocation => '$exe login <console-url>';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    if (argResults!.rest.length != 1) usageException('give the console URL');
    final url = argResults!.rest.single;
    String token;
    if (stdin.hasTerminal) {
      stdout.write('Personal access token for $url (hidden): ');
      stdin.echoMode = false;
      try {
        token = (stdin.readLineSync(encoding: utf8) ?? '').trim();
      } finally {
        stdin.echoMode = true;
        stdout.writeln();
      }
    } else {
      token = (await utf8.decodeStream(stdin)).trim();
    }
    if (token.isEmpty) throw Aborted('empty token');
    try {
      final me = await ConsoleTransport(url, token).whoami();
      log.ok('signed in to $url as ${me['user'] ?? me['email'] ?? '?'}');
    } on ConsoleUnreachable catch (e) {
      log.warn('$e; the token is stored anyway');
    }
    final store = TokenStore();
    await store.write(url, token);
    log.info('token stored in ${store.where}');
    return 0;
  }
}

class LogoutCommand extends PodshipCommand {
  @override
  String get name => 'logout';
  @override
  String get description =>
      'Forget the token of a console (revoke it in the console too).';
  @override
  String get invocation => '$exe logout [<console-url>]';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    final url = argResults!.rest.isNotEmpty
        ? argResults!.rest.single
        : consoleUrl;
    await TokenStore().delete(url);
    log.ok('forgot the token of $url');
    return 0;
  }
}

class WhoamiCommand extends PodshipCommand {
  @override
  String get name => 'whoami';
  @override
  String get description =>
      'Who the console token belongs to, and the roles per project and environment.';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    try {
      final me = await console.whoami();
      json ? printJson(me) : me.forEach((k, v) => stdout.writeln('$k: $v'));
      return 0;
    } on ConsoleUnreachable catch (e) {
      log.error('$e');
      return 1;
    } on ConsoleRefused catch (e) {
      log.error('$e');
      return 3;
    }
  }
}

class OperationsCommand extends PodshipCommand {
  @override
  String get name => 'operations';
  @override
  String get description =>
      'The operation catalog of the protocol: stable names, parameters as JSON schema (for consoles and MCP tools).';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    if (json) {
      printJson({
        'protocol': protocolVersion,
        'operations': [for (final o in operations) o.toJson()],
      });
    } else {
      for (final o in operations) {
        stdout.writeln(
          '${o.name.padRight(20)} ${o.mutating ? (o.destructive ? 'destructive' : 'changes   ') : 'read      '}  ${o.description}',
        );
      }
    }
    return 0;
  }
}
