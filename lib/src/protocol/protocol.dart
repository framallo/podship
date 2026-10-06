// The podship operation protocol, version 1.
//
// One request names an operation and its parameters. The answer is a stream
// of event envelopes; the last event has type `result`. Every client speaks
// it: the CLI over ssh runs it in-process, a console runs it on its server
// and streams the events back, an MCP server exposes each operation as a
// tool. Operation names and parameter names are stable: new versions add,
// never rename.
//
// Request  (JSON):  {"protocol":1,"id":"…","operation":"deploy","project":"shop",
//                    "env":"staging","params":{…},"dry_run":false}
// Events   (NDJSON): {"protocol":1,"request_id":"…","seq":0,"event":{"type":"operation_started",…}}
//                    …
//                    {"protocol":1,"request_id":"…","seq":42,"event":{"type":"result","ok":true,…}}
//
// Read operations put their value in the result's `data.value`.

import 'dart:async';
import 'dart:math';

import '../api/events.dart';
import '../api/models.dart';
import '../api/podship.dart';
import '../config/config.dart';
import '../ops/context.dart';
import '../providers/provider.dart';

/// The protocol version. A server rejects a request with a newer version.
const protocolVersion = 1;

/// A parameter of an operation.
class ParamSpec {
  const ParamSpec(
    this.name,
    this.type,
    this.description, {
    this.required = false,
    this.values,
  });
  final String name;

  /// `string`, `boolean`, `integer`, `string[]` or `object` (string values).
  final String type;
  final String description;
  final bool required;

  /// Allowed values, for enums.
  final List<String>? values;

  Map<String, Object?> toJsonSchema() => {
    'type': switch (type) {
      'string[]' => 'array',
      _ => type,
    },
    if (type == 'string[]') 'items': {'type': 'string'},
    if (type == 'object') 'additionalProperties': {'type': 'string'},
    'description': description,
    'enum': ?values,
  };
}

/// An operation of the protocol.
class OperationSpec {
  const OperationSpec(
    this.name,
    this.description, {
    this.params = const [],
    this.mutating = true,
    this.destructive = false,
    this.needsEnv = true,
    this.confirmation,
    this.approval,
    this.planOperation,
  });

  /// The stable name, like `deploy` or `backup.restore`.
  final String name;
  final String description;
  final List<ParamSpec> params;
  final bool mutating;

  /// Can destroy data or stop production.
  final bool destructive;
  final bool needsEnv;

  /// The parameter that must hold a typed confirmation (the project or
  /// environment name), when the operation needs one.
  final String? confirmation;

  /// `owner`: the operation changes DNS, tunnels, Access or SES. It runs
  /// only with the `plan_id` of a plan the owner approved; an MCP client
  /// may only call [planOperation]. `owner_if_cloudflare`: the same, when
  /// the `provider` param is `cloudflare`.
  final String? approval;

  /// The read operation that returns the plan to approve.
  final String? planOperation;

  /// Whether [params] make this operation need the owner's approval.
  bool needsApproval(Map<String, Object?> params) =>
      approval == 'owner' ||
      (approval == 'owner_if_cloudflare' && params['provider'] == 'cloudflare');

  /// A JSON schema for the parameters (an MCP tool's `inputSchema`).
  Map<String, Object?> inputSchema() => {
    'type': 'object',
    'properties': {
      if (needsEnv)
        'env': {
          'type': 'string',
          'description': 'The environment, like staging or production.',
        },
      'dry_run': {
        'type': 'boolean',
        'description': 'Plan only; change nothing.',
      },
      for (final p in params) p.name: p.toJsonSchema(),
    },
    'required': [
      if (needsEnv) 'env',
      for (final p in params)
        if (p.required) p.name,
    ],
  };

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'mutating': mutating,
    'destructive': destructive,
    'confirmation': ?confirmation,
    'approval': ?approval,
    'plan_operation': ?planOperation,
    'input_schema': inputSchema(),
  };
}

const _reason = ParamSpec(
  'skip_tests_reason',
  'string',
  'Skip the test stage, with this reason (recorded in history).',
);
const _confirmEnv = ParamSpec(
  'confirm_env',
  'string',
  'The environment name, typed by the user, to confirm an untested deploy.',
);
const _planId = ParamSpec(
  'plan_id',
  'string',
  'The id of the plan the owner approved; the operation refuses to run when the fresh plan differs.',
);
const _hosts = ParamSpec(
  'hosts',
  'string[]',
  'Only these hosts (default: every domain of the environment).',
);
const _provider = ParamSpec(
  'provider',
  'string',
  'cloudflare: also manage DNS records and Access apps through the Cloudflare API.',
  values: ['cloudflare'],
);
const _confirmProject = ParamSpec(
  'confirm_project',
  'string',
  'The project name, typed by the user.',
  required: true,
);

/// Every operation, by name.
const operations = <OperationSpec>[
  OperationSpec(
    'deploy',
    'Build, upload and start a new release; roll back if it is not healthy.',
    destructive: true,
    confirmation: 'confirm_env',
    params: [
      ParamSpec('ref', 'string', 'The git ref to deploy (default: build.ref).'),
      ParamSpec('skip_web', 'boolean', 'Do not build Flutter web.'),
      ParamSpec(
        'skip_backup',
        'boolean',
        'No database backup before the switch.',
      ),
      ParamSpec(
        'public_check',
        'boolean',
        'Also check the public health URL (default true).',
      ),
      _reason,
      _confirmEnv,
    ],
  ),
  OperationSpec(
    'rollback',
    'Switch to a previous release (code only), or restore a backup too with with_db.',
    destructive: true,
    params: [
      ParamSpec('to', 'string', 'The release id (default: the previous one).'),
      ParamSpec('with_db', 'string', 'A backup stamp to restore first.'),
      ParamSpec(
        'confirm_project',
        'string',
        'The project name, typed by the user; required with with_db.',
      ),
    ],
  ),
  OperationSpec(
    'promote',
    'Run on `env` the exact release (files and images) that runs on `from`.',
    destructive: true,
    params: [
      ParamSpec('from', 'string', 'The source environment.', required: true),
      ParamSpec(
        'release',
        'string',
        'The release (default: the one running on from).',
      ),
      _reason,
      _confirmEnv,
    ],
  ),
  OperationSpec(
    'restart',
    'Recreate the containers of the current release.',
    destructive: true,
    params: [ParamSpec('services', 'string[]', 'Only these services.')],
  ),
  OperationSpec(
    'adopt',
    'Record a running setup as a release, without restarting it.',
    params: [
      ParamSpec(
        'compose_dir',
        'string',
        'The folder the compose project was started from.',
      ),
    ],
  ),
  OperationSpec('link', 'Register the environment in the server registry.'),
  OperationSpec(
    'destroy',
    'Remove the environment completely.',
    destructive: true,
    confirmation: 'confirm_project',
    params: [
      ParamSpec('purge_backups', 'boolean', 'Also delete its backups.'),
      _confirmProject,
    ],
  ),
  OperationSpec(
    'unlock',
    'Remove the environment lock left by a client that died.',
  ),
  OperationSpec('backup.now', 'Take a backup now.'),
  OperationSpec(
    'backup.drill',
    'Restore a backup into a throwaway container and compare row counts.',
    params: [ParamSpec('stamp', 'string', 'The backup (default: the newest).')],
  ),
  OperationSpec(
    'backup.restore',
    'Replace the database (and with volumes, the volumes) with a backup.',
    destructive: true,
    confirmation: 'confirm_project',
    params: [
      ParamSpec('stamp', 'string', 'The backup (default: the newest).'),
      ParamSpec(
        'from',
        'string',
        'Another environment whose backup to restore.',
      ),
      ParamSpec('volumes', 'boolean', 'Also replace the Docker volumes.'),
      _confirmProject,
    ],
  ),
  OperationSpec(
    'backup.schedule',
    'Install (or with remove, remove) the daily backup.',
    params: [ParamSpec('remove', 'boolean', 'Remove the schedule.')],
  ),
  OperationSpec(
    'env.set',
    'Set plain variables in the environment .env.',
    params: [ParamSpec('values', 'object', 'NAME → value.', required: true)],
  ),
  OperationSpec(
    'env.unset',
    'Remove variables.',
    params: [ParamSpec('names', 'string[]', 'Names.', required: true)],
  ),
  OperationSpec(
    'secret.set',
    'Set a secret (the value is never shown again).',
    params: [
      ParamSpec('name', 'string', 'The name.', required: true),
      ParamSpec('value', 'string', 'The value.', required: true),
      ParamSpec(
        'password',
        'boolean',
        'A passwords.yaml key instead of a .env variable.',
      ),
    ],
  ),
  OperationSpec(
    'secret.unset',
    'Remove secrets.',
    params: [
      ParamSpec('names', 'string[]', 'Names.', required: true),
      ParamSpec('password', 'boolean', 'passwords.yaml keys.'),
    ],
  ),
  OperationSpec(
    'domain.add',
    'Route the domains of the environment (with provider cloudflare: also DNS and Access).',
    approval: 'owner_if_cloudflare',
    planOperation: 'domain.plan',
    params: [_hosts, _provider, _planId],
  ),
  OperationSpec(
    'domain.remove',
    'Remove domain routes (with provider cloudflare: also the DNS records that point here).',
    destructive: true,
    approval: 'owner_if_cloudflare',
    planOperation: 'domain.plan',
    params: [_hosts, _provider, _planId],
  ),
  OperationSpec(
    'domain.plan',
    'The plan of domain.add (or with remove, domain.remove): routes, DNS, Access, with before and after.',
    mutating: false,
    params: [
      _hosts,
      _provider,
      ParamSpec('remove', 'boolean', 'Plan the removal.'),
    ],
  ),
  OperationSpec(
    'dns.plan',
    'The DNS records the domains need, against Cloudflare (create/update/delete with before and after).',
    mutating: false,
    params: [_hosts, ParamSpec('remove', 'boolean', 'Plan the removal.')],
  ),
  OperationSpec(
    'dns.apply',
    'Create, update or delete the DNS records of the domains in Cloudflare.',
    approval: 'owner',
    planOperation: 'dns.plan',
    params: [
      _hosts,
      ParamSpec('remove', 'boolean', 'Remove the records that point here.'),
      _planId,
    ],
  ),
  OperationSpec(
    'dns.list',
    'DNS records of the domains (or of a whole zone) in Cloudflare.',
    mutating: false,
    params: [ParamSpec('zone', 'string', 'A whole zone, like example.com.')],
  ),
  OperationSpec(
    'dns.drift',
    'Where each domain points, against the environment\'s tunnel.',
    mutating: false,
  ),
  OperationSpec(
    'tunnel.list',
    'Cloudflare Tunnels of the account, with status and how each is managed.',
    mutating: false,
  ),
  OperationSpec(
    'tunnel.plan',
    'The plan of a tunnel route (or with remove, unroute).',
    mutating: false,
    params: [_hosts, ParamSpec('remove', 'boolean', 'Plan the removal.')],
  ),
  OperationSpec(
    'tunnel.route',
    'Route hostnames through the environment\'s tunnel (API for remotely-managed tunnels, config.yml for local ones).',
    approval: 'owner',
    planOperation: 'tunnel.plan',
    params: [_hosts, _planId],
  ),
  OperationSpec(
    'tunnel.unroute',
    'Remove hostnames from the environment\'s tunnel.',
    destructive: true,
    approval: 'owner',
    planOperation: 'tunnel.plan',
    params: [_hosts, _planId],
  ),
  OperationSpec(
    'tunnel.create',
    'Create a remotely-managed Cloudflare Tunnel.',
    approval: 'owner',
    params: [ParamSpec('name', 'string', 'The tunnel name.', required: true)],
  ),
  OperationSpec(
    'email.status',
    'Whether the sender can send through SES: identity, DKIM, sandbox, quota.',
    mutating: false,
  ),
  OperationSpec(
    'email.plan',
    'What email.setup would change: SES identity, DKIM records, MAIL FROM.',
    mutating: false,
  ),
  OperationSpec(
    'email.setup',
    'Create the SES identity, its DKIM records and the MAIL FROM domain.',
    approval: 'owner',
    planOperation: 'email.plan',
    params: [_planId],
  ),
  OperationSpec(
    'email.test',
    'Send a test email from the environment\'s sender.',
    approval: 'owner',
    params: [
      ParamSpec(
        'to',
        'string',
        'The recipient (default: success@simulator.amazonses.com).',
      ),
    ],
  ),
  OperationSpec(
    'app.plan',
    'The whole app setup as one plan: registry and ports, tunnel route, DNS, Access, TLS, SES.',
    mutating: false,
  ),
  OperationSpec(
    'app.setup',
    'Apply the app setup plan, then check DNS (DoH) and the public health URL.',
    approval: 'owner',
    planOperation: 'app.plan',
    params: [_planId],
  ),
  OperationSpec(
    'app.teardown.plan',
    'What app.teardown would remove.',
    mutating: false,
    params: [
      ParamSpec(
        'email',
        'boolean',
        'Also the SES identity this environment created.',
      ),
    ],
  ),
  OperationSpec(
    'app.teardown',
    'Remove the DNS records, tunnel routes and Access apps of the environment (and with email, its SES identity).',
    destructive: true,
    approval: 'owner',
    planOperation: 'app.teardown.plan',
    params: [
      ParamSpec(
        'email',
        'boolean',
        'Also the SES identity this environment created.',
      ),
      _planId,
    ],
  ),
  OperationSpec(
    'server.bootstrap',
    'Prepare the server: Docker, compose, age, zstd, firewall, folders.',
    params: [ParamSpec('caddy', 'boolean', 'Also install Caddy.')],
  ),
  OperationSpec(
    'server.create',
    'Create a server at a provider, bootstrap and register it.',
    needsEnv: false,
    destructive: false,
    params: [
      ParamSpec(
        'provider',
        'string',
        'The provider.',
        required: true,
        values: ['hostinger', 'vultr'],
      ),
      ParamSpec('name', 'string', 'A name for the server.', required: true),
      ParamSpec(
        'region',
        'string',
        'The provider region, like mex for Vultr.',
        required: true,
      ),
      ParamSpec('plan', 'string', 'The provider plan.', required: true),
      ParamSpec(
        'image',
        'string',
        'The OS image (default: the newest Ubuntu LTS).',
      ),
      ParamSpec('ssh_keys', 'string[]', 'Public keys for root.'),
    ],
  ),
  OperationSpec(
    'server.destroy',
    'Delete a server at its provider.',
    needsEnv: false,
    destructive: true,
    confirmation: 'confirm_name',
    params: [
      ParamSpec(
        'provider',
        'string',
        'The provider.',
        required: true,
        values: ['hostinger', 'vultr'],
      ),
      ParamSpec(
        'id',
        'string',
        'The provider id of the server.',
        required: true,
      ),
      ParamSpec(
        'confirm_name',
        'string',
        'The server name, typed by the user.',
        required: true,
      ),
    ],
  ),
  OperationSpec(
    'status',
    'Current release, releases, containers, health, disk.',
    mutating: false,
  ),
  OperationSpec(
    'releases.list',
    'Releases kept on the server.',
    mutating: false,
  ),
  OperationSpec(
    'releases.overview',
    'What runs where: every environment, its current release and commit, and its releases.',
    mutating: false,
    needsEnv: false,
  ),
  OperationSpec(
    'releases.containing',
    'Which environments run a release that contains a commit.',
    mutating: false,
    needsEnv: false,
    params: [
      ParamSpec('sha', 'string', 'A commit (sha or ref).', required: true),
    ],
  ),
  OperationSpec('backup.list', 'Backups on the server.', mutating: false),
  OperationSpec(
    'history',
    'Operation history (who, when, outcome).',
    mutating: false,
    params: [
      ParamSpec('limit', 'integer', 'How many records (default 20).'),
      ParamSpec('all_projects', 'boolean', 'Every project on the server.'),
    ],
  ),
  OperationSpec(
    'env.list',
    'Variables (secret values hidden).',
    mutating: false,
  ),
  OperationSpec('secret.list', 'Secret names.', mutating: false),
  OperationSpec('domain.list', 'Domains, routes and DNS.', mutating: false),
  OperationSpec(
    'db.migrate.status',
    'Applied migrations against the release.',
    mutating: false,
  ),
  OperationSpec(
    'projects.list',
    'Projects on the server of the environment.',
    mutating: false,
  ),
  OperationSpec(
    'server.status',
    'Every project, container and the disk of the server.',
    mutating: false,
  ),
  OperationSpec(
    'logs',
    'Container logs (the last lines).',
    mutating: false,
    params: [
      ParamSpec('services', 'string[]', 'Only these services.'),
      ParamSpec('since', 'string', 'Like 10m or 2026-10-06T10:00.'),
      ParamSpec('tail', 'integer', 'Lines per service (default 100).'),
    ],
  ),
];

OperationSpec? operationSpec(String name) =>
    operations.where((o) => o.name == name).firstOrNull;

/// A request to run an operation.
class OperationRequest {
  OperationRequest({
    required this.operation,
    required this.project,
    this.env,
    this.params = const {},
    this.dryRun = false,
    String? id,
    this.protocol = protocolVersion,
    this.origin,
  }) : id = id ?? newRequestId();

  factory OperationRequest.fromJson(Map<String, Object?> j) => OperationRequest(
    protocol: (j['protocol'] as num? ?? protocolVersion).toInt(),
    id: j['id'] as String?,
    operation: '${j['operation']}',
    project: '${j['project']}',
    env: j['env'] as String?,
    params: (j['params'] as Map?)?.cast<String, Object?>() ?? const {},
    dryRun: j['dry_run'] == true,
    origin: j['origin'] as String?,
  );

  final int protocol;
  final String id;
  final String operation;
  final String project;
  final String? env;
  final Map<String, Object?> params;
  final bool dryRun;

  /// Who asks: `cli`, `console` or `mcp`. A console sets it; an MCP
  /// request may only plan operations that need the owner's approval.
  final String? origin;

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'id': id,
    'operation': operation,
    'project': project,
    'env': ?env,
    'params': params,
    'dry_run': dryRun,
    'origin': ?origin,
  };
}

/// A random request id.
String newRequestId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// One event of a response stream.
class EventEnvelope {
  EventEnvelope(this.requestId, this.seq, this.event);
  final String requestId;
  final int seq;
  final Map<String, Object?> event;

  Map<String, Object?> toJson() => {
    'protocol': protocolVersion,
    'request_id': requestId,
    'seq': seq,
    'event': event,
  };
}

/// Runs [req] with [podship] and returns the events as JSON maps, ending
/// with a `result` event. This is what a console runs on its side.
Stream<Map<String, Object?>> dispatch(
  Podship podship,
  OperationRequest req,
) async* {
  if (req.protocol > protocolVersion) {
    yield _resultJson(
      req,
      false,
      'protocol ${req.protocol} is newer than this server ($protocolVersion)',
    );
    return;
  }
  final spec = operationSpec(req.operation);
  if (spec == null) {
    yield _resultJson(req, false, 'unknown operation "${req.operation}"');
    return;
  }
  if (req.project != podship.config.project) {
    yield _resultJson(
      req,
      false,
      'this request is for project ${req.project}, not ${podship.config.project}',
    );
    return;
  }
  final env = req.env;
  if (spec.needsEnv &&
      (env == null || !podship.config.environments.containsKey(env))) {
    yield _resultJson(req, false, 'unknown environment "$env"');
    return;
  }
  final p = req.params;
  String? s(String k) => p[k] as String?;
  bool b(String k) => p[k] == true;
  List<String> l(String k) => [
    for (final x in (p[k] as List? ?? const [])) '$x',
  ];
  final api = podship.copyWith(dryRun: req.dryRun);

  // Typed confirmations must match.
  if (spec.confirmation == 'confirm_project' &&
      s('confirm_project') != podship.config.project) {
    yield _resultJson(
      req,
      false,
      '${spec.name} needs confirm_project = "${podship.config.project}"',
    );
    return;
  }
  if (spec.name == 'rollback' &&
      s('with_db') != null &&
      s('confirm_project') != podship.config.project) {
    yield _resultJson(
      req,
      false,
      'rollback with_db needs confirm_project = "${podship.config.project}"',
    );
    return;
  }
  // DNS, tunnel and SES changes: the owner approves a plan id.
  if (spec.needsApproval(p) && !req.dryRun) {
    final planOp = spec.planOperation;
    if (req.origin == 'mcp') {
      yield _resultJson(
        req,
        false,
        '${spec.name} needs the owner\'s approval: MCP clients may only plan'
        '${planOp == null ? '' : ' (call $planOp, or ${spec.name} with dry_run)'}; '
        'the owner approves the plan in the console',
      );
      return;
    }
    if (planOp != null && s('plan_id') == null) {
      yield _resultJson(
        req,
        false,
        '${spec.name} needs plan_id: get the plan with $planOp and have the owner approve it',
      );
      return;
    }
  }
  final skipReason = s('skip_tests_reason');
  final confirmedUntested = skipReason != null && s('confirm_env') == env;

  Operation? op;
  Object? value;
  try {
    switch (spec.name) {
      case 'deploy':
        op = api.deploy(
          env!,
          ref: s('ref'),
          skipTestsReason: skipReason,
          confirmedUntested: confirmedUntested,
          options: DeployOptions(
            skipWeb: b('skip_web'),
            skipBackup: b('skip_backup'),
            publicCheck: p['public_check'] != false,
          ),
        );
      case 'rollback':
        op = api.rollback(env!, to: s('to'), withDb: s('with_db'));
      case 'promote':
        op = api.promote(
          s('from')!,
          env!,
          release: s('release'),
          skipTestsReason: skipReason,
          confirmedUntested: confirmedUntested,
        );
      case 'restart':
        op = api.restart(env!, services: l('services'));
      case 'adopt':
        op = api.adopt(env!, composeDir: s('compose_dir'));
      case 'link':
        op = api.link(env!);
      case 'destroy':
        op = api.destroy(env!, purgeBackups: b('purge_backups'));
      case 'unlock':
        op = api.unlock(env!);
      case 'backup.now':
        op = api.backupNow(env!);
      case 'backup.drill':
        op = api.backupDrill(env!, stamp: s('stamp'));
      case 'backup.restore':
        op = api.backupRestore(
          env!,
          stamp: s('stamp'),
          fromEnv: s('from'),
          volumes: b('volumes'),
        );
      case 'backup.schedule':
        op = api.backupSchedule(env!, remove: b('remove'));
      case 'env.set':
        op = api.envSet(env!, {
          for (final e in ((p['values'] as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}',
        });
      case 'env.unset':
        op = api.envUnset(env!, l('names'));
      case 'secret.set':
        op = api.secretSet(
          env!,
          s('name')!,
          s('value')!,
          password: b('password'),
        );
      case 'secret.unset':
        op = api.secretUnset(env!, l('names'), password: b('password'));
      case 'domain.add':
        op = api.domainAdd(
          env!,
          hosts: l('hosts'),
          provider: s('provider'),
          planId: s('plan_id'),
        );
      case 'domain.remove':
        op = api.domainRemove(
          env!,
          hosts: l('hosts'),
          provider: s('provider'),
          planId: s('plan_id'),
        );
      case 'domain.plan':
        value = (await api.domainPlan(
          env!,
          hosts: l('hosts'),
          remove: b('remove'),
          provider: s('provider'),
        )).toJson();
      case 'dns.plan':
        value = (await api.dnsPlan(
          env!,
          hosts: l('hosts'),
          remove: b('remove'),
        )).toJson();
      case 'dns.apply':
        op = api.dnsApply(
          env!,
          hosts: l('hosts'),
          remove: b('remove'),
          planId: s('plan_id'),
        );
      case 'dns.list':
        value = [
          for (final r in await api.dnsRecords(env!, zone: s('zone')))
            r.toJson(),
        ];
      case 'dns.drift':
        value = [for (final d in await api.dnsDrift(env!)) d.toJson()];
      case 'tunnel.list':
        value = [for (final t in await api.tunnels(env!)) t.toJson()];
      case 'tunnel.plan':
        value = (await api.tunnelPlan(
          env!,
          hosts: l('hosts'),
          remove: b('remove'),
        )).toJson();
      case 'tunnel.route':
        op = api.tunnelRoute(env!, hosts: l('hosts'), planId: s('plan_id'));
      case 'tunnel.unroute':
        op = api.tunnelUnroute(env!, hosts: l('hosts'), planId: s('plan_id'));
      case 'tunnel.create':
        op = api.tunnelCreate(env!, s('name')!);
      case 'email.status':
        value = (await api.emailStatus(env!)).toJson();
      case 'email.plan':
        value = (await api.emailPlan(env!)).toJson();
      case 'email.setup':
        op = api.emailSetup(env!, planId: s('plan_id'));
      case 'email.test':
        op = api.emailTest(
          env!,
          to: s('to') ?? 'success@simulator.amazonses.com',
        );
      case 'app.plan':
        value = (await api.appPlan(env!)).toJson();
      case 'app.setup':
        op = api.appSetup(env!, planId: s('plan_id'));
      case 'app.teardown.plan':
        value = (await api.teardownPlan(env!, email: b('email'))).toJson();
      case 'app.teardown':
        op = api.appTeardown(env!, planId: s('plan_id'), email: b('email'));
      case 'server.bootstrap':
        op = api.bootstrap(env!, caddy: b('caddy'));
      case 'server.create':
        op = api.serverCreate(
          s('provider')!,
          ServerSpec(
            name: s('name')!,
            region: s('region')!,
            plan: s('plan')!,
            image: s('image'),
            sshKeys: l('ssh_keys'),
          ),
        );
      case 'server.destroy':
        op = api.serverDestroy(s('provider')!, s('id')!);
      case 'scale':
        op = api.scale(env!, (p['replicas'] as num).toInt());
      case 'loadtest':
        op = api.loadtest(
          env!,
          path: s('path') ?? '/health',
          vus: (p['vus'] as num? ?? 10).toInt(),
          duration: s('duration') ?? '30s',
        );
      case 'status':
        value = (await api.status(env!)).toJson();
      case 'releases.list':
        final cur = await api.currentRelease(env!);
        value = [
          for (final r in await api.releases(env)) r.toJson(current: cur),
        ];
      case 'releases.overview':
        value = await api.overview();
      case 'releases.containing':
        value = await api.releasesContaining(s('sha')!);
      case 'backup.list':
        value = [for (final x in await api.backups(env!)) x.toJson()];
      case 'history':
        value = [
          for (final h in await api.history(
            env!,
            limit: (p['limit'] as num? ?? 20).toInt(),
            allProjects: b('all_projects'),
          ))
            h.toJson(),
        ];
      case 'env.list':
        value = [for (final v in await api.envList(env!)) v.toJson()];
      case 'secret.list':
        value = await api.secretList(env!);
      case 'domain.list':
        value = [for (final d in await api.domains(env!)) d.toJson()];
      case 'db.migrate.status':
        value = (await api.migrateStatus(env!)).toJson();
      case 'projects.list':
        value = [
          for (final e in (await api.projects(env!)).entries.values) e.toMap(),
        ];
      case 'server.status':
        value = (await api.serverStatus(env!)).toJson();
      case 'logs':
        value = await api
            .logs(
              env!,
              services: l('services'),
              since: s('since'),
              tail: (p['tail'] as num? ?? 100).toInt(),
            )
            .toList();
      default:
        yield _resultJson(
          req,
          false,
          '${spec.name} is not available through this server',
        );
        return;
    }
  } on Aborted catch (e) {
    yield _resultJson(req, false, e.message);
    return;
  } on ConfigException catch (e) {
    yield _resultJson(req, false, '$e');
    return;
  } catch (e) {
    yield _resultJson(req, false, '$e');
    return;
  }
  if (op != null) {
    await for (final e in op.events) {
      yield e.toJson();
    }
    return;
  }
  yield OperationFinished(
    OperationResult(
      operation: spec.name,
      ok: true,
      duration: Duration.zero,
      project: req.project,
      env: env,
      data: {'value': value},
    ),
  ).toJson();
}

Map<String, Object?> _resultJson(
  OperationRequest req,
  bool ok,
  String? error,
) => OperationFinished(
  OperationResult(
    operation: req.operation,
    ok: ok,
    duration: Duration.zero,
    project: req.project,
    env: req.env,
    error: error,
  ),
).toJson();
