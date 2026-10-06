// dns, tunnel, domain (with Cloudflare), email and app commands.
//
// Every command that changes DNS, a tunnel, Access or SES prints its plan
// first (create/update/delete with before and after, and a plan id), then
// asks for approval: `--yes`, or "y" in a terminal. `--plan` prints the
// plan and stops. `--plan-id <id>` applies only if the fresh plan still
// has that id. Through a console, the plan comes from the console and the
// apply carries its id, which the console checks against the owner's
// approval.

import 'dart:io';

import '../api/podship.dart';
import '../integrations/changes.dart';
import '../integrations/planner.dart';
import '../ops/context.dart';
import '../protocol/protocol.dart';
import 'base.dart';
import 'db_commands.dart';

/// A command that plans changes and applies them after an approval.
abstract class ChangeCommand extends PodshipCommand {
  ChangeCommand() {
    argParser
      ..addFlag(
        'plan',
        negatable: false,
        help:
            'Print the plan (create/update/delete, before and after) and change nothing.',
      )
      ..addOption(
        'plan-id',
        help:
            'Apply only if the fresh plan has this id (from an earlier --plan).',
      );
  }

  @override
  bool get mutating => true;

  bool get planOnly => argResults!['plan'] == true || dryRun;

  /// The plan, computed here.
  Future<ChangeSet> plan();

  /// The read operation that returns the same plan from a console.
  OperationRequest planRequest();

  /// The operation that applies the plan with id [planId].
  Operation apply(String planId);

  @override
  Future<int> execute() async {
    ChangeSet set;
    if (via == 'console') {
      Object? value;
      final code = await runRemoteRead(planRequest(), (v) => value = v);
      if (code != 0) return code;
      set = ChangeSet.fromJson(value as Map);
    } else {
      set = await plan();
    }
    if (json) {
      printJson(set.toJson());
    } else {
      stdout.write(set.render());
    }
    if (planOnly) return 0;
    final wanted = argResults!['plan-id'] as String?;
    if (wanted != null && wanted != set.id) {
      throw Aborted(
        'the plan is now ${set.id}, not $wanted: review it and run again',
      );
    }
    if (set.isEmpty && !applyWhenEmpty) {
      log.ok('nothing to change');
      return 0;
    }
    if (!ctx.confirm(
      'Apply plan ${set.id} (${set.pending.length} change(s))?',
    )) {
      throw Aborted('cancelled; nothing was changed');
    }
    return runOp(apply(set.id));
  }

  /// Run the operation even with nothing to change (for its checks).
  bool get applyWhenEmpty => false;

  List<String>? get hosts => argResults!.rest.isEmpty ? null : argResults!.rest;
}

// ------------------------------------------------------------------- dns

class DnsPlanCommand extends PodshipCommand {
  DnsPlanCommand() {
    argParser.addFlag(
      'remove',
      negatable: false,
      help: 'Plan the removal of the records that point here.',
    );
  }
  @override
  String get name => 'plan';
  @override
  String get description =>
      'The DNS records the domains need, against Cloudflare: create/update/delete with before and after.';
  @override
  String get invocation => '$exe dns plan [HOST…] --env <env>';
  @override
  OperationRequest? get consoleRead => request('dns.plan', {
    'hosts': argResults!.rest,
    'remove': argResults!['remove'] == true,
  });
  @override
  Future<int> execute() async {
    final set = await api.dnsPlan(
      env.name,
      hosts: argResults!.rest.isEmpty ? null : argResults!.rest,
      remove: argResults!['remove'] == true,
    );
    json ? printJson(set.toJson()) : stdout.write(set.render());
    return 0;
  }
}

class DnsApplyCommand extends ChangeCommand {
  DnsApplyCommand() {
    argParser.addFlag(
      'remove',
      negatable: false,
      help: 'Delete the records that point here.',
    );
  }
  @override
  String get name => 'apply';
  @override
  String get description =>
      'Create, update or delete the DNS records of the domains in Cloudflare (plan, approve, apply).';
  @override
  String get invocation =>
      '$exe dns apply [HOST…] --env <env> [--yes] [--plan-id <id>]';
  bool get remove => argResults?['remove'] == true;
  @override
  bool get destructive => remove;
  @override
  Future<ChangeSet> plan() => api.dnsPlan(
    (remove ? guardedEnv : env).name,
    hosts: hosts,
    remove: remove,
  );
  @override
  OperationRequest planRequest() =>
      request('dns.plan', {'hosts': argResults!.rest, 'remove': remove});
  @override
  Operation apply(String planId) =>
      api.dnsApply(env.name, hosts: hosts, remove: remove, planId: planId);
}

class DnsListCommand extends PodshipCommand {
  DnsListCommand() {
    argParser.addOption('zone', help: 'Every record of this zone instead.');
  }
  @override
  String get name => 'list';
  @override
  String get description =>
      'The DNS records of the domains (or a zone) in Cloudflare, and drift.';
  @override
  OperationRequest? get consoleRead =>
      request('dns.list', {'zone': ?argResults!['zone'] as String?});
  @override
  Future<int> execute() async {
    final zone = argResults!['zone'] as String?;
    final records = await api.dnsRecords(env.name, zone: zone);
    final drift = zone == null
        ? await api.dnsDrift(env.name)
        : const <DnsDrift>[];
    if (json) {
      printJson({
        'records': [for (final r in records) r.toJson()],
        'drift': [for (final d in drift) d.toJson()],
      });
      return 0;
    }
    for (final r in records) {
      stdout.writeln(
        '${r.describe()}${r.comment == null ? '' : '   # ${r.comment}'}',
      );
    }
    for (final d in drift) {
      stdout.writeln(d.describe());
    }
    return 0;
  }
}

// ---------------------------------------------------------------- tunnel

class TunnelListCommand extends PodshipCommand {
  @override
  String get name => 'list';
  @override
  String get description =>
      'Cloudflare Tunnels of the account: status, connections, and remote or local management.';
  @override
  OperationRequest? get consoleRead => request('tunnel.list');
  @override
  Future<int> execute() async {
    final list = await api.tunnels(env.name);
    if (json) {
      printJson([for (final t in list) t.toJson()]);
      return 0;
    }
    final mine = env.proxy.tunnelId;
    for (final t in list) {
      stdout.writeln(
        '${t.id == mine ? '*' : ' '} ${t.name.padRight(24)} ${t.id}  ${t.status.padRight(9)} '
        '${t.connections} conn  ${t.remoteConfig ? 'remote' : 'local (config.yml)'}',
      );
    }
    return 0;
  }
}

class TunnelRouteCommand extends ChangeCommand {
  TunnelRouteCommand(this._remove);
  final bool _remove;
  @override
  String get name => _remove ? 'unroute' : 'route';
  @override
  String get description => _remove
      ? 'Remove hostnames from the environment\'s tunnel.'
      : 'Route hostnames through the environment\'s tunnel (API for remotely-managed tunnels, config.yml for local ones).';
  @override
  String get invocation => '$exe tunnel $name [HOST…] --env <env>';
  @override
  bool get destructive => _remove;
  @override
  Future<ChangeSet> plan() => api.tunnelPlan(
    (_remove ? guardedEnv : env).name,
    hosts: hosts,
    remove: _remove,
  );
  @override
  OperationRequest planRequest() =>
      request('tunnel.plan', {'hosts': argResults!.rest, 'remove': _remove});
  @override
  Operation apply(String planId) => _remove
      ? api.tunnelUnroute(env.name, hosts: hosts, planId: planId)
      : api.tunnelRoute(env.name, hosts: hosts, planId: planId);
}

class TunnelCreateCommand extends PodshipCommand {
  @override
  String get name => 'create';
  @override
  String get description =>
      'Create a remotely-managed Cloudflare Tunnel in the environment\'s account.';
  @override
  String get invocation => '$exe tunnel create <name> --env <env>';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    if (argResults!.rest.length != 1) usageException('give the tunnel name');
    final name = argResults!.rest.single;
    if (!dryRun && !ctx.confirm('Create the Cloudflare Tunnel "$name"?')) {
      throw Aborted('cancelled');
    }
    return runOp(api.tunnelCreate(env.name, name));
  }
}

/// `podship tunnel forward`: the port forward that `podship tunnel` was
/// before tunnels had subcommands.
class TunnelForwardCommand extends TunnelCommand {
  @override
  String get name => 'forward';
}

// ---------------------------------------------------------------- domain

class DomainChangeCommand extends ChangeCommand {
  DomainChangeCommand(this._remove) {
    argParser.addOption(
      'provider',
      allowed: ['cloudflare'],
      help:
          'Also create (or delete) the DNS records and Access apps through the Cloudflare API.',
    );
  }
  final bool _remove;
  @override
  String get name => _remove ? 'remove' : 'add';
  @override
  String get description => _remove
      ? 'Remove the routes of a domain (with --provider cloudflare, also its DNS records and Access app).'
      : 'Route a domain from podship.yaml (Cloudflare Tunnel or Caddy with TLS); with --provider cloudflare, '
            'also its DNS record and Access app.';
  @override
  String get invocation =>
      '$exe domain $name [HOST…] [--env <env>] [--provider cloudflare] [--plan]';
  @override
  bool get destructive => _remove;
  String? get provider => argResults!['provider'] as String?;

  bool get _cloudflare {
    final e = env;
    return provider == 'cloudflare' ||
        e.dns.provider.name == 'cloudflare' ||
        e.proxy.remoteManaged;
  }

  @override
  Future<int> execute() async {
    final e = _remove ? guardedEnv : env;
    if (_cloudflare) return super.execute();
    // Without Cloudflare: the proxy only, as before.
    return runOp(
      _remove
          ? api.domainRemove(e.name, hosts: argResults!.rest)
          : api.domainAdd(e.name, hosts: argResults!.rest),
    );
  }

  @override
  Future<ChangeSet> plan() => api.domainPlan(
    env.name,
    hosts: hosts,
    remove: _remove,
    provider: provider,
  );
  @override
  OperationRequest planRequest() => request('domain.plan', {
    'hosts': argResults!.rest,
    'remove': _remove,
    'provider': ?provider,
  });
  @override
  Operation apply(String planId) => _remove
      ? api.domainRemove(
          env.name,
          hosts: hosts,
          provider: provider,
          planId: planId,
        )
      : api.domainAdd(
          env.name,
          hosts: hosts,
          provider: provider,
          planId: planId,
        );
}

// ----------------------------------------------------------------- email

class EmailStatusCommand extends PodshipCommand {
  @override
  String get name => 'status';
  @override
  String get description =>
      'Whether the sender can send through SES: identity (or verified parent domain), DKIM, MAIL FROM, sandbox, quota.';
  @override
  OperationRequest? get consoleRead => request('email.status');
  @override
  Future<int> execute() async {
    final c = await api.emailStatus(env.name);
    if (json) {
      printJson(c.toJson());
      return c.canSend ? 0 : 1;
    }
    stdout.writeln(
      '${c.address} in SES ${c.region}: ${c.canSend ? 'CAN SEND' : 'CANNOT SEND'}'
      '${c.sendingIdentity == null ? '' : ' (identity ${c.sendingIdentity})'}',
    );
    final a = c.account;
    stdout.writeln(
      'account: ${a.production ? 'production' : 'SANDBOX'}, ${a.sent24h.toInt()}/${a.max24h.toInt()} in 24 h, '
      '${a.maxRate.toInt()}/s${a.enforcement == null ? '' : ', ${a.enforcement}'}',
    );
    for (final e in c.identities.entries) {
      final i = e.value;
      if (i == null) {
        stdout.writeln('  ${e.key}: not in SES');
        continue;
      }
      stdout.writeln(
        '  ${e.key}: ${i.verifiedForSending ? 'verified' : i.verificationStatus ?? '?'}, DKIM ${i.dkimStatus ?? '?'}'
        '${i.mailFromDomain == null ? '' : ', MAIL FROM ${i.mailFromDomain} (${i.mailFromStatus})'}',
      );
      if (!i.verifiedForSending) {
        for (final r in (i.toJson()['dkim_records'] as List)) {
          stdout.writeln('    needs $r');
        }
      }
    }
    for (final p in c.problems) {
      stdout.writeln('!! $p');
    }
    return c.canSend ? 0 : 1;
  }
}

class EmailSetupCommand extends ChangeCommand {
  @override
  String get name => 'setup';
  @override
  String get description =>
      'Make the sender able to send: SES identity, DKIM records (through Cloudflare), MAIL FROM and its MX/SPF.';
  @override
  Future<ChangeSet> plan() => api.emailPlan(env.name);
  @override
  OperationRequest planRequest() => request('email.plan');
  @override
  Operation apply(String planId) => api.emailSetup(env.name, planId: planId);
}

class EmailTestCommand extends PodshipCommand {
  EmailTestCommand() {
    argParser.addOption(
      'to',
      defaultsTo: 'success@simulator.amazonses.com',
      help:
          'The recipient. In the SES sandbox only verified addresses (and the simulator) receive mail.',
    );
  }
  @override
  String get name => 'test';
  @override
  String get description =>
      'Send a test email from the environment\'s sender through SES.';
  @override
  bool get mutating => true;
  @override
  Future<int> execute() async {
    final to = argResults!['to'] as String;
    if (!dryRun &&
        !ctx.confirm('Send a test email from ${env.email?.from} to $to?')) {
      throw Aborted('cancelled');
    }
    return runOp(api.emailTest(env.name, to: to));
  }
}

// ------------------------------------------------------------------- app

class AppSetupCommand extends ChangeCommand {
  @override
  String get name => 'setup';
  @override
  String get description =>
      'Set up an app with one plan and one approval: registry and ports, tunnel route, DNS, Access, TLS check, '
      'SES sender (+ DKIM), then DNS over DoH and the public health check.';
  @override
  bool get applyWhenEmpty => true;
  @override
  Future<ChangeSet> plan() => api.appPlan(env.name);
  @override
  OperationRequest planRequest() => request('app.plan');
  @override
  Operation apply(String planId) => api.appSetup(env.name, planId: planId);
}

class AppTeardownCommand extends ChangeCommand {
  AppTeardownCommand() {
    argParser.addFlag(
      'email',
      negatable: false,
      help:
          'Also delete the SES identity, if this environment created it (tag podship=<project>/<env>).',
    );
  }
  @override
  String get name => 'teardown';
  @override
  String get description =>
      'Undo app setup: DNS records that point here, tunnel routes, Access apps (and with --email, the SES identity). '
      'The registry entry stays; `podship destroy` removes the environment.';
  @override
  bool get destructive => true;
  bool get email => argResults!['email'] == true;
  @override
  Future<ChangeSet> plan() => api.teardownPlan(guardedEnv.name, email: email);
  @override
  OperationRequest planRequest() =>
      request('app.teardown.plan', {'email': email});
  @override
  Operation apply(String planId) =>
      api.appTeardown(env.name, planId: planId, email: email);
}
