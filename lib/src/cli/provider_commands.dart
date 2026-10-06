// provider login/offers, server create/destroy.

import 'dart:convert' show utf8;
import 'dart:io';

import '../ops/backup_ops.dart';
import '../ops/context.dart';
import '../protocol/tokens.dart';
import '../providers/providers.dart';
import 'base.dart';

class ProviderLoginCommand extends PodshipCommand {
  @override
  String get name => 'login';
  @override
  String get description =>
      'Store a provider API token in the secret store (read from stdin or a hidden prompt).';
  @override
  String get invocation => '$exe provider login <vultr|hostinger>';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    if (argResults!.rest.length != 1) usageException('give the provider');
    final provider = argResults!.rest.single;
    String token;
    if (stdin.hasTerminal) {
      stdout.write('$provider API token (hidden): ');
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
    final store = TokenStore();
    await store.write('provider:$provider', token);
    log.ok('stored the $provider token in ${store.where}');
    return 0;
  }
}

class ProviderOffersCommand extends PodshipCommand {
  ProviderOffersCommand() {
    argParser.addOption('country', help: 'Only this country code, like MX.');
  }
  @override
  String get name => 'offers';
  @override
  String get description => 'Regions, plans and monthly prices of a provider.';
  @override
  String get invocation =>
      '$exe provider offers <vultr|hostinger> [--country MX]';
  @override
  bool get takesEnv => false;
  @override
  Future<int> execute() async {
    if (argResults!.rest.length != 1) usageException('give the provider');
    registerBuiltInProviders();
    final provider = argResults!.rest.single;
    final token = TokenStore().read('provider:$provider') ?? '';
    if (token.isEmpty && provider != 'vultr') {
      throw Aborted(
        'no $provider token: run `podship provider login $provider`',
      );
    }
    final country = (argResults!['country'] as String?)?.toUpperCase();
    final offers = [
      for (final o in await providerFor(provider, token).offers())
        if (country == null || o.country.toUpperCase() == country) o,
    ];
    if (json) {
      printJson([for (final o in offers) o.toJson()]);
      return 0;
    }
    for (final o in offers) {
      stdout.writeln('${o.region.padRight(6)} ${o.city}, ${o.country}');
      final plans = o.plans.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final p in plans.take(8)) {
        stdout.writeln('    ${p.key.padRight(34)} \$${p.value}/month');
      }
    }
    return 0;
  }
}

class ServerCreateCommand extends PodshipCommand {
  ServerCreateCommand() {
    argParser
      ..addOption('provider', mandatory: true, allowed: ['vultr', 'hostinger'])
      ..addOption('name', mandatory: true, help: 'A label and host name.')
      ..addOption(
        'region',
        mandatory: true,
        help: 'Like mex (Vultr, Mexico City) or a Hostinger data center id.',
      )
      ..addOption(
        'plan',
        mandatory: true,
        help: 'Like vc2-2c-4gb (Vultr) or a Hostinger price id.',
      )
      ..addOption('image', help: 'OS image id (default: newest Ubuntu LTS).')
      ..addMultiOption(
        'ssh-key',
        defaultsTo: ['~/.ssh/id_ed25519.pub'],
        help: 'Public key files for root.',
      )
      ..addFlag(
        'bootstrap',
        defaultsTo: true,
        help: 'Run server bootstrap when it is up.',
      )
      ..addOption(
        'confirm',
        help: 'The server name, to confirm the purchase without a terminal.',
      );
  }
  @override
  String get name => 'create';
  @override
  String get description =>
      'Create a server at a provider (it costs money), wait for it, and bootstrap it.';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final a = argResults!;
    final keys = [
      for (final k in a['ssh-key'] as List<String>)
        if (File(expandHome(k)).existsSync())
          File(expandHome(k)).readAsStringSync().trim(),
    ];
    final spec = ServerSpec(
      name: a['name'] as String,
      region: a['region'] as String,
      plan: a['plan'] as String,
      image: a['image'] as String?,
      sshKeys: keys,
    );
    if (!dryRun) {
      confirmEnvName(
        spec.name,
        'This BUYS a server at ${a['provider']} (${spec.plan} in ${spec.region}).',
        a['confirm'] as String?,
      );
    }
    return runOp(
      api.serverCreate(
        a['provider'] as String,
        spec,
        bootstrap: a['bootstrap'] == true,
      ),
    );
  }
}

class ServerDestroyCommand extends PodshipCommand {
  ServerDestroyCommand() {
    argParser
      ..addOption('provider', mandatory: true, allowed: ['vultr', 'hostinger'])
      ..addOption('id', mandatory: true, help: 'The provider id of the server.')
      ..addOption(
        'name',
        mandatory: true,
        help: 'The server name, which you must type to confirm.',
      )
      ..addOption(
        'confirm',
        help: 'The server name, to confirm without a terminal.',
      );
  }
  @override
  String get name => 'destroy';
  @override
  String get description =>
      'Delete a server at its provider. Everything on it is lost.';
  @override
  bool get takesEnv => false;
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final a = argResults!;
    confirmEnvName(
      a['name'] as String,
      'This DELETES ${a['name']} (${a['id']}) at ${a['provider']}.',
      a['confirm'] as String?,
    );
    configOrEmpty;
    return runOp(api.serverDestroy(a['provider'] as String, a['id'] as String));
  }
}
