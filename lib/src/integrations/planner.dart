// Planners: compare what an environment wants (podship.yaml) with what
// Cloudflare and SES have, and return [Change]s. Reads go through
// read-only clients; only a change's `apply` uses the live client.
//
// Ownership: podship marks DNS records with the comment
// `podship <project>/<env>`, names Access apps `podship <project>/<env> …`
// and tags SES identities `podship=<project>/<env>`. Removing only touches
// what points to this environment (DNS) or carries its mark (Access, SES).

import '../config/config.dart';
import '../ops/resolve.dart';
import 'changes.dart';
import 'cloudflare.dart';
import 'ses.dart';

/// The mark podship puts on what it creates.
String ownerMark(String project, String env) => 'podship $project/$env';

class CloudflarePlanner {
  CloudflarePlanner(this.cf, {required this.project, required this.env})
    : ro = cf.readOnly();

  /// The live client (used only by `apply`).
  final CloudflareApi cf;

  /// The read-only client (used for planning).
  final CloudflareApi ro;
  final String project;
  final EnvConfig env;

  String get owner => ownerMark(project, env.name);

  final _zones = <String, CfZone>{};

  /// The zone of [host] (cached).
  Future<CfZone> zone(String host) async {
    for (final z in _zones.values) {
      if (host == z.name || host.endsWith('.${z.name}')) return z;
    }
    final z = await ro.zoneFor(host, zoneName: env.dns.zone);
    return _zones[z.name] = z;
  }

  /// The account: `dns.account_id`, else the account of [host]'s zone.
  Future<String> accountId([String? host]) async {
    if (env.dns.accountId != null) return env.dns.accountId!;
    final h =
        host ??
        (env.domains.isNotEmpty
            ? env.domains.first.host
            : throw ConfigException(
                'set environments.${env.name}.dns.account_id (no domain to find the account from)',
              ));
    return (await zone(h)).accountId;
  }

  String get tunnelId =>
      env.proxy.tunnelId ??
      (throw ConfigException(
        'environments.${env.name}.proxy.tunnel_id is required',
      ));

  /// The records [host] needs for this environment's proxy.
  List<CfDnsRecord> wantedRecords(String host) {
    switch (env.proxy.kind) {
      case ProxyKind.cloudflareTunnel:
        return [
          CfDnsRecord(
            type: 'CNAME',
            name: host,
            content: '$tunnelId.cfargotunnel.com',
            proxied: true,
            comment: owner,
          ),
        ];
      case ProxyKind.caddy:
        final d = env.dns;
        if (d.ipv4 == null && d.ipv6 == null) {
          throw ConfigException(
            'environments.${env.name}.dns.ipv4 (or ipv6) is required for Caddy records',
          );
        }
        return [
          if (d.ipv4 != null)
            CfDnsRecord(
              type: 'A',
              name: host,
              content: d.ipv4!,
              proxied: d.proxied ?? false,
              comment: owner,
            ),
          if (d.ipv6 != null)
            CfDnsRecord(
              type: 'AAAA',
              name: host,
              content: d.ipv6!,
              proxied: d.proxied ?? false,
              comment: owner,
            ),
        ];
      case ProxyKind.none:
        throw ConfigException(
          'environments.${env.name}.proxy.kind is none: there is nothing to point DNS at',
        );
    }
  }

  /// Changes that make the records named [name] equal [wanted]. Records of
  /// a conflicting type (A/AAAA against CNAME) are deleted first. TXT
  /// records are matched by their first word (`v=spf1`), so other TXT
  /// records of the name stay.
  Future<List<Change>> records(String name, List<CfDnsRecord> wanted) async {
    final z = await zone(name);
    final existing = await ro.dnsRecords(z.id, name: name);
    final wantTypes = wanted.map((w) => w.type).toSet();
    const addressTypes = {'A', 'AAAA', 'CNAME'};
    final conflicting = [
      for (final e in existing)
        if (wantTypes.any(addressTypes.contains) &&
            addressTypes.contains(e.type) &&
            !wantTypes.contains(e.type))
          e,
    ];
    final out = <Change>[
      for (final e in conflicting)
        _deleteRecord(z, e, 'conflicts with ${wanted.first.type}'),
    ];
    for (final w in wanted) {
      final same = existing
          .where((e) => e.type == w.type)
          .where(
            (e) =>
                w.type != 'TXT' || _txtKind(e.content) == _txtKind(w.content),
          );
      final match = same.where((e) => e.sameAs(w)).firstOrNull;
      if (match != null) {
        out.add(
          Change.unchanged(
            'dns_record',
            '${w.type} ${w.name}',
            state: match.describe(),
          ),
        );
        continue;
      }
      final old = same.firstOrNull;
      if (old == null) {
        out.add(
          Change(
            kind: ChangeKind.create,
            resource: 'dns_record',
            key: '${w.type} ${w.name}',
            after: {'summary': w.describe(), ...w.body()},
            apply: () async {
              final made = await cf.createDns(z.id, w);
              return Undo(
                'delete ${w.describe()}',
                () => cf.deleteDns(z.id, made.id!),
                data: {'zone': z.name, 'record_id': made.id},
              );
            },
          ),
        );
      } else {
        final mine = old.comment == owner;
        out.add(
          Change(
            kind: ChangeKind.update,
            resource: 'dns_record',
            key: '${w.type} ${w.name}',
            before: {'summary': old.describe(), ...old.toJson()},
            after: {'summary': w.describe(), ...w.body()},
            note: mine
                ? null
                : 'this record was not created by $owner${old.comment == null ? '' : ' (comment: ${old.comment})'}',
            apply: () async {
              await cf.updateDns(z.id, old.id!, w);
              return Undo(
                'restore ${old.describe()}',
                () => cf.updateDns(z.id, old.id!, old),
                data: {'zone': z.name, 'record_id': old.id},
              );
            },
          ),
        );
      }
    }
    return out;
  }

  static String _txtKind(String content) =>
      content.replaceAll('"', '').trim().split(' ').first.toLowerCase();

  Change _deleteRecord(CfZone z, CfDnsRecord e, String why) => Change(
    kind: ChangeKind.delete,
    resource: 'dns_record',
    key: '${e.type} ${e.name}',
    before: {'summary': e.describe(), ...e.toJson()},
    note: why,
    apply: () async {
      await cf.deleteDns(z.id, e.id!);
      return Undo(
        'recreate ${e.describe()}',
        () => cf.createDns(z.id, e).then((_) {}),
        data: {'zone': z.name, 'record': e.toJson()},
      );
    },
  );

  /// Removes the records of [name] that equal [wanted] (point to this
  /// environment). Records that point elsewhere stay.
  Future<List<Change>> removeRecords(
    String name,
    List<CfDnsRecord> wanted,
  ) async {
    final z = await zone(name);
    final existing = await ro.dnsRecords(z.id, name: name);
    final out = <Change>[];
    for (final w in wanted) {
      final same = existing.where((e) => e.type == w.type).toList();
      final ours = same
          .where((e) => e.sameAs(w) || (e.comment == owner && w.type != 'TXT'))
          .toList();
      for (final e in ours) {
        out.add(_deleteRecord(z, e, 'points to this environment'));
      }
      if (ours.isEmpty) {
        out.add(
          Change.unchanged(
            'dns_record',
            '${w.type} $name',
            state: same.isEmpty ? 'no record' : same.first.describe(),
            note: same.isEmpty
                ? null
                : 'points elsewhere, not to ${env.name}; left alone',
          ),
        );
      }
    }
    return out;
  }

  /// DNS changes for [hosts] (default: every domain of the environment).
  Future<List<Change>> hostRecords(
    List<String> hosts, {
    bool remove = false,
  }) async => [
    for (final h in hosts)
      ...(remove
          ? await removeRecords(h, wantedRecords(h))
          : await records(h, wantedRecords(h))),
  ];

  /// Ingress changes on the remotely-managed tunnel for [routes] (none
  /// removes the host).
  Future<List<Change>> tunnelIngress(
    Map<String, List<ResolvedRoute>> routes,
  ) async {
    if (routes.isEmpty) return const [];
    final acc = await accountId(routes.keys.first);
    final tid = tunnelId;
    final cfg = await ro.tunnelConfig(acc, tid);
    _requireRemote(cfg, tid);
    final out = <Change>[];
    for (final e in routes.entries) {
      final host = e.key;
      final before = cfg.rulesOf(host);
      final after = [
        for (final r in [
          ...e.value.where((r) => r.path != null),
          ...e.value.where((r) => r.path == null),
        ])
          CfIngressRule(
            hostname: host,
            path: r.path,
            service: 'http://localhost:${r.port}',
          ),
      ];
      String text(List<CfIngressRule> rs) =>
          rs.isEmpty ? 'no rules' : rs.map((r) => r.describe()).join('; ');
      final key = 'tunnel $tid: $host';
      if (text(before) == text(after)) {
        out.add(Change.unchanged('tunnel_ingress', key, state: text(after)));
        continue;
      }
      out.add(
        Change(
          kind: before.isEmpty
              ? ChangeKind.create
              : after.isEmpty
              ? ChangeKind.delete
              : ChangeKind.update,
          resource: 'tunnel_ingress',
          key: key,
          before: before.isEmpty
              ? null
              : {
                  'summary': text(before),
                  'rules': [for (final r in before) r.toJson()],
                },
          after: after.isEmpty
              ? null
              : {
                  'summary': text(after),
                  'rules': [for (final r in after) r.toJson()],
                },
          apply: () async {
            final now = await cf.tunnelConfig(acc, tid);
            _requireRemote(now, tid);
            await cf.putTunnelConfig(acc, tid, now.withHost(host, after));
            return Undo('restore the tunnel rules of $host', () async {
              final again = await cf.tunnelConfig(acc, tid);
              await cf.putTunnelConfig(acc, tid, again.withHost(host, before));
            }, data: {'tunnel': tid, 'host': host});
          },
        ),
      );
    }
    return out;
  }

  void _requireRemote(CfTunnelConfig cfg, String tid) {
    if (cfg.source != 'cloudflare') {
      throw ConfigException(
        'tunnel $tid is managed locally (its config.yml on the host). '
        'Set environments.${env.name}.proxy.config (and proxy.managed: local) '
        'so podship edits the file instead of the API.',
      );
    }
  }

  /// Access apps for the domains of [hosts] that have `access:`.
  Future<List<Change>> access(List<String> hosts, {bool remove = false}) async {
    final wanted = [
      for (final d in env.domains)
        if (hosts.contains(d.host) && d.access != null) d,
    ];
    if (wanted.isEmpty) return const [];
    final acc = await accountId(wanted.first.host);
    final apps = await ro.accessApps(acc);
    final out = <Change>[];
    for (final d in wanted) {
      final a = d.access!;
      final name = '$owner ${d.host}';
      final existing = apps.where((x) => x.domain == d.host).toList();
      final who = [...a.emails, ...a.emailDomains.map((x) => '@$x')].join(', ');
      if (remove) {
        final ours = existing
            .where((x) => x.name.startsWith('podship '))
            .toList();
        for (final x in ours) {
          out.add(
            Change(
              kind: ChangeKind.delete,
              resource: 'access_app',
              key: d.host,
              before: {'summary': '${x.name} (${x.id})', ...x.toJson()},
              apply: () async {
                await cf.deleteAccessApp(acc, x.id);
                return Undo('recreate the Access app of ${d.host}', () async {
                  await cf.createAccessApp(
                    acc,
                    name: name,
                    domain: d.host,
                    emails: a.emails,
                    emailDomains: a.emailDomains,
                    sessionDuration: a.sessionDuration,
                  );
                });
              },
            ),
          );
        }
        if (ours.isEmpty) {
          out.add(
            Change.unchanged(
              'access_app',
              d.host,
              state: existing.isEmpty ? 'no app' : existing.first.name,
              note: existing.isEmpty
                  ? null
                  : 'not created by podship; left alone',
            ),
          );
        }
        continue;
      }
      if (existing.isNotEmpty) {
        out.add(
          Change.unchanged(
            'access_app',
            d.host,
            state: existing.first.name,
            note:
                'podship does not compare policies; edit them in the Zero Trust dashboard',
          ),
        );
        continue;
      }
      out.add(
        Change(
          kind: ChangeKind.create,
          resource: 'access_app',
          key: d.host,
          after: {
            'summary': '$name: allow $who (session ${a.sessionDuration})',
            ...accessAppBody(
              name: name,
              domain: d.host,
              emails: a.emails,
              emailDomains: a.emailDomains,
              sessionDuration: a.sessionDuration,
            ),
          },
          apply: () async {
            final made = await cf.createAccessApp(
              acc,
              name: name,
              domain: d.host,
              emails: a.emails,
              emailDomains: a.emailDomains,
              sessionDuration: a.sessionDuration,
            );
            return Undo(
              'delete the Access app of ${d.host}',
              () => cf.deleteAccessApp(acc, made.id),
              data: {'app_id': made.id},
            );
          },
        ),
      );
    }
    return out;
  }

  /// TLS: Cloudflare's edge certificate (Universal SSL) covers the apex
  /// and one level of subdomains. Deeper names need an advanced
  /// certificate.
  Future<List<PlanCheck>> tls(List<String> hosts) async {
    final out = <PlanCheck>[];
    for (final h in hosts) {
      try {
        final z = await zone(h);
        final depth = h.split('.').length - z.name.split('.').length;
        final universal = await ro.universalSsl(z.id);
        out.add(
          PlanCheck(
            'TLS $h',
            universal && depth <= 1,
            !universal
                ? 'Universal SSL is off for ${z.name}: turn it on or add a certificate'
                : depth > 1
                ? 'Universal SSL covers *.${z.name} only; $h needs an advanced certificate (or Total TLS)'
                : 'covered by the Universal SSL certificate of ${z.name}',
          ),
        );
      } on CloudflareException catch (e) {
        out.add(PlanCheck('TLS $h', false, 'could not check: ${e.message}'));
      }
    }
    return out;
  }

  /// Where the DNS of each domain points, against this environment. A
  /// CNAME to another name of the same zone (www → apex) is followed, up
  /// to 3 hops.
  Future<List<DnsDrift>> drift() async {
    final out = <DnsDrift>[];
    for (final d in env.domains) {
      final wanted = wantedRecords(d.host);
      final z = await zone(d.host);
      var name = d.host;
      final chain = <String>[];
      var recs = await ro.dnsRecords(z.id, name: name);
      for (var hop = 0; hop < 3; hop++) {
        final cname = recs.where((r) => r.type == 'CNAME').firstOrNull;
        if (cname == null || wanted.any((w) => w.sameAs(cname))) break;
        final target = cname.content.toLowerCase().replaceAll(
          RegExp(r'\.$'),
          '',
        );
        if (target != z.name && !target.endsWith('.${z.name}')) break;
        chain.add(name);
        name = target;
        recs = await ro.dnsRecords(z.id, name: name);
      }
      final c = classifyDns(name, recs, [
        for (final w in wanted)
          CfDnsRecord(
            type: w.type,
            name: name,
            content: w.content,
            proxied: w.proxied,
          ),
      ]);
      out.add(
        chain.isEmpty
            ? c
            : DnsDrift(
                d.host,
                c.state,
                wanted.map((w) => w.describe()).join(', '),
                '${[...chain, name].join(' → ')}: ${c.actual}',
              ),
      );
    }
    return out;
  }
}

/// Whether a domain's DNS points to its environment.
class DnsDrift {
  DnsDrift(this.host, this.state, this.expected, this.actual);
  final String host;

  /// `ok`, `missing`, `other_tunnel` or `elsewhere`.
  final String state;
  final String expected;
  final String actual;
  bool get ok => state == 'ok';
  Map<String, Object?> toJson() => {
    'host': host,
    'state': state,
    'expected': expected,
    'actual': actual,
  };

  String describe() => switch (state) {
    'ok' => '$host: ok ($actual)',
    'missing' => '$host: NO RECORD (wants $expected)',
    'other_tunnel' =>
      '$host: DRIFT: points to another tunnel ($actual), not $expected',
    _ => '$host: DRIFT: points to $actual, not $expected',
  };
}

/// Compares the records of [host] with [wanted].
DnsDrift classifyDns(
  String host,
  List<CfDnsRecord> records,
  List<CfDnsRecord> wanted,
) {
  final expected = wanted.map((w) => w.describe()).join(', ');
  final relevant = [
    for (final r in records)
      if (const {'A', 'AAAA', 'CNAME'}.contains(r.type)) r,
  ];
  if (relevant.isEmpty) return DnsDrift(host, 'missing', expected, 'none');
  final actual = relevant.map((r) => r.describe()).join(', ');
  final ok = wanted.every((w) => relevant.any((r) => r.sameAs(w)));
  if (ok) return DnsDrift(host, 'ok', expected, actual);
  final otherTunnel = relevant.any(
    (r) => r.type == 'CNAME' && r.content.endsWith('.cfargotunnel.com'),
  );
  return DnsDrift(
    host,
    otherTunnel ? 'other_tunnel' : 'elsewhere',
    expected,
    actual,
  );
}

/// SES: the sender of an environment, its identity, DKIM and MAIL FROM.
class EmailPlanner {
  EmailPlanner(
    this.ses, {
    required this.email,
    required this.project,
    required this.env,
    this.dns,
  }) : ro = ses.readOnly();
  final SesApi ses;
  final SesApi ro;
  final EmailConfig email;
  final String project;
  final String env;

  /// The DNS planner, when the domain's DNS is in Cloudflare.
  final CloudflarePlanner? dns;

  String get owner => ownerMark(project, env);
  Map<String, String> get tags => {'podship': '$project/$env'};

  /// DNS changes through Cloudflare, or a check that lists the records to
  /// add by hand when Cloudflare cannot manage them.
  Future<(List<Change>, List<PlanCheck>)> _records(
    String what,
    String name,
    List<CfDnsRecord> wanted,
  ) async {
    final manual = wanted.map((w) => w.describe()).join('; ');
    final d = dns;
    if (d == null) {
      return (
        const <Change>[],
        [PlanCheck(what, false, 'add these DNS records: $manual')],
      );
    }
    try {
      return (await d.records(name, wanted), const <PlanCheck>[]);
    } on CloudflareException catch (e) {
      return (
        const <Change>[],
        [
          PlanCheck(
            what,
            false,
            'Cloudflare cannot manage $name (${e.message}); add these DNS records: $manual',
          ),
        ],
      );
    }
  }

  List<CfDnsRecord> _dkim(String domain, List<String> tokens) => [
    for (final r in dkimRecords(domain, tokens))
      CfDnsRecord(
        type: 'CNAME',
        name: r.$1,
        content: r.$2,
        proxied: false,
        comment: owner,
      ),
  ];

  List<CfDnsRecord> _mailFrom(String name) {
    final r = mailFromRecords(ses.region);
    return [
      CfDnsRecord(
        type: 'MX',
        name: name,
        content: r.mx,
        priority: 10,
        comment: owner,
      ),
      CfDnsRecord(type: 'TXT', name: name, content: r.spf, comment: owner),
    ];
  }

  /// The plan that lets [EmailConfig.from] send.
  Future<ChangeSet> plan() async {
    final check = await checkSender(ro, email.from);
    final changes = <Change>[];
    final checks = <PlanCheck>[
      PlanCheck(
        'SES account (${ses.region})',
        check.account.production && check.account.sendingEnabled,
        check.account.production
            ? 'production access; ${check.account.sent24h.toInt()} of ${check.account.max24h.toInt()} sent in 24 h, ${check.account.maxRate.toInt()}/s'
            : 'SANDBOX: only verified recipients; request production access in the SES console',
      ),
    ];
    final identityName =
        check.sendingIdentity ?? email.identity ?? email.domain;
    SesIdentity? identity = check.identities.containsKey(identityName)
        ? check.identities[identityName]
        : await ro.identity(identityName);
    final creating = identity == null;
    SesIdentity? created;

    if (check.canSend) {
      checks.add(
        PlanCheck(
          'sender ${check.address}',
          true,
          'can send through the verified identity ${check.sendingIdentity}',
        ),
      );
    } else if (creating) {
      changes.add(
        Change(
          kind: ChangeKind.create,
          resource: 'ses_identity',
          key: identityName,
          after: {
            'summary':
                'domain identity $identityName in ${ses.region} with Easy DKIM, tag podship=$project/$env',
            'region': ses.region,
            'tags': tags,
          },
          apply: () async {
            created = await ses.createIdentity(identityName, tags: tags);
            return Undo(
              'delete the SES identity $identityName',
              () => ses.deleteIdentity(identityName),
              data: {'identity': identityName, 'region': ses.region},
            );
          },
        ),
      );
      if (dns != null) {
        try {
          final z = await dns!.zone(identityName);
          changes.add(
            Change(
              kind: ChangeKind.create,
              resource: 'dns_record',
              key: 'DKIM CNAMEs of $identityName',
              after: {
                'summary':
                    '3 × CNAME <token>._domainkey.$identityName → <token>.dkim.amazonses.com '
                    '(the tokens come from SES when the identity is created)',
              },
              apply: () async {
                final tokens =
                    created?.dkimTokens ??
                    (await ses.identity(identityName))?.dkimTokens ??
                    const <String>[];
                final made = <String>[];
                for (final r in _dkim(identityName, tokens)) {
                  final have = await dns!.cf.dnsRecords(z.id, name: r.name);
                  if (have.any((h) => h.sameAs(r))) continue;
                  made.add((await dns!.cf.createDns(z.id, r)).id!);
                }
                return Undo(
                  'delete the DKIM CNAMEs of $identityName',
                  () async {
                    for (final id in made) {
                      await dns!.cf.deleteDns(z.id, id);
                    }
                  },
                  data: {'zone': z.name, 'record_ids': made},
                );
              },
            ),
          );
        } on CloudflareException catch (e) {
          checks.add(
            PlanCheck(
              'DKIM $identityName',
              false,
              'Cloudflare cannot manage $identityName (${e.message}); after setup, '
                  '`podship email status` lists the 3 CNAMEs to add by hand',
            ),
          );
        }
      } else {
        checks.add(
          PlanCheck(
            'DKIM $identityName',
            false,
            'after setup, `podship email status` lists the 3 CNAMEs to add by hand',
          ),
        );
      }
    } else {
      // SES knows the identity but it cannot send yet: publish its DKIM.
      final (c, k) = await _records(
        'DKIM $identityName',
        identityName,
        _dkim(identityName, identity.dkimTokens),
      );
      for (final x in c) {
        changes.add(x);
      }
      checks.addAll(k);
      checks.add(
        PlanCheck(
          'identity $identityName',
          false,
          'verification ${identity.verificationStatus ?? '?'}, DKIM ${identity.dkimStatus ?? '?'}: '
              'SES verifies it within minutes to 72 h after the DKIM records resolve',
        ),
      );
    }

    final mf = email.mailFrom;
    if (mf != null) {
      if (mf != identityName && !mf.endsWith('.$identityName')) {
        throw ConfigException(
          'email.mail_from $mf must be a subdomain of the identity $identityName',
        );
      }
      final current = identity?.mailFromDomain;
      if (current != mf) {
        changes.add(
          Change(
            kind: current == null ? ChangeKind.create : ChangeKind.update,
            resource: 'ses_mail_from',
            key: identityName,
            before: current == null ? null : {'summary': 'MAIL FROM $current'},
            after: {
              'summary': 'MAIL FROM $mf (on MX failure: use amazonses.com)',
            },
            apply: () async {
              await ses.putMailFrom(identityName, mf);
              return Undo(
                current == null
                    ? 'remove the MAIL FROM of $identityName'
                    : 'restore MAIL FROM $current',
                () => ses.putMailFrom(identityName, current),
              );
            },
          ),
        );
      } else {
        changes.add(
          Change.unchanged(
            'ses_mail_from',
            identityName,
            state: 'MAIL FROM $mf (${identity?.mailFromStatus ?? '?'})',
          ),
        );
      }
      final (c, k) = await _records('MAIL FROM $mf', mf, _mailFrom(mf));
      changes.addAll(c);
      checks.addAll(k);
    }
    return ChangeSet(
      'email for ${email.from} ($project/$env)',
      changes,
      checks: checks,
    );
  }

  /// Removes the identity (only when it carries this environment's tag),
  /// its DKIM records and MAIL FROM records that point to SES.
  Future<ChangeSet> teardown() async {
    final name = email.identity ?? email.domain;
    final id = await ro.identity(name);
    final changes = <Change>[];
    if (id == null) {
      changes.add(Change.unchanged('ses_identity', name, state: 'not in SES'));
    } else if (id.tags['podship'] != '$project/$env') {
      changes.add(
        Change.unchanged(
          'ses_identity',
          name,
          state: 'exists',
          note:
              'not created by $project/$env (tag podship=${id.tags['podship'] ?? 'none'}); left alone',
        ),
      );
    } else {
      final d = dns;
      if (d != null) {
        changes.addAll(await _tryRemove(d, name, _dkim(name, id.dkimTokens)));
        if (email.mailFrom != null) {
          changes.addAll(
            await _tryRemove(d, email.mailFrom!, _mailFrom(email.mailFrom!)),
          );
        }
      }
      changes.add(
        Change(
          kind: ChangeKind.delete,
          resource: 'ses_identity',
          key: name,
          before: {
            'summary': 'domain identity $name in ${ses.region}',
            ...id.toJson(),
          },
          note:
              'a deleted identity cannot be restored with the same DKIM tokens',
          apply: () async {
            await ses.deleteIdentity(name);
            return null;
          },
        ),
      );
    }
    return ChangeSet('remove email identity of $project/$env', changes);
  }

  Future<List<Change>> _tryRemove(
    CloudflarePlanner d,
    String name,
    List<CfDnsRecord> wanted,
  ) async {
    try {
      final out = <Change>[];
      for (final w in wanted) {
        out.addAll(await d.removeRecords(name, [w]));
      }
      return out;
    } on CloudflareException {
      return const [];
    }
  }
}
