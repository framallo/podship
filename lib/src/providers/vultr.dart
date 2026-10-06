// Vultr (API v2). Region `mex` is Mexico City. Billed by the hour.

import 'dart:convert';

import 'provider.dart';

class VultrProvider extends ServerProvider {
  VultrProvider(String token)
    : _api = JsonApi('https://api.vultr.com/v2', token);
  final JsonApi _api;

  /// Ubuntu 24.04 LTS x64.
  static const ubuntuLts = 2284;

  @override
  String get name => 'vultr';

  @override
  Future<List<ProviderOffer>> offers() async {
    // Both lists are public.
    final regions =
        ((await JsonApi.publicGet(
                  'https://api.vultr.com/v2/regions?per_page=500',
                ))
                as Map)['regions']
            as List;
    final plans =
        ((await JsonApi.publicGet(
                  'https://api.vultr.com/v2/plans?type=vc2&per_page=500',
                ))
                as Map)['plans']
            as List;
    return [
      for (final r in regions.cast<Map>())
        ProviderOffer('${r['id']}', '${r['city']}', '${r['country']}', {
          for (final p in plans.cast<Map>())
            if ((p['locations'] as List).contains(r['id']))
              '${p['id']}': p['monthly_cost'] as num,
        }),
    ];
  }

  ProviderServer _server(Map j) {
    final i = (j['instance'] ?? j) as Map;
    final ready =
        i['status'] == 'active' &&
        i['server_status'] == 'ok' &&
        i['main_ip'] != '0.0.0.0';
    return ProviderServer(
      id: '${i['id']}',
      name: '${i['label']}',
      status: ready ? 'ready' : '${i['status']}/${i['server_status']}',
      ipv4: i['main_ip'] == null || i['main_ip'] == '0.0.0.0'
          ? null
          : '${i['main_ip']}',
      ipv6: (i['v6_main_ip'] as String?)?.isEmpty ?? true
          ? null
          : i['v6_main_ip'] as String,
      region: '${i['region']}',
      plan: '${i['plan']}',
    );
  }

  @override
  Future<ProviderServer> create(ServerSpec spec) async {
    final keyIds = <String>[];
    for (final (n, k) in spec.sshKeys.indexed) {
      final r = await _api.call('POST', '/ssh-keys', {
        'name': '${spec.name}-podship-$n',
        'ssh_key': k.trim(),
      });
      keyIds.add('${((r as Map)['ssh_key'] as Map)['id']}');
    }
    final fw = await _api.call('POST', '/firewalls', {
      'description': '${spec.name} (podship)',
    });
    final fwId = '${((fw as Map)['firewall_group'] as Map)['id']}';
    for (final port in spec.firewallPorts) {
      for (final v in [('v4', '0.0.0.0'), ('v6', '::')]) {
        await _api.call('POST', '/firewalls/$fwId/rules', {
          'ip_type': v.$1,
          'protocol': 'TCP',
          'subnet': v.$2,
          'subnet_size': 0,
          'port': '$port',
          'notes': 'podship',
        });
      }
    }
    final r = await _api.call('POST', '/instances', {
      'region': spec.region,
      'plan': spec.plan,
      'os_id': int.tryParse(spec.image ?? '') ?? ubuntuLts,
      'label': spec.name,
      'hostname': spec.name,
      'sshkey_id': keyIds,
      'backups': 'disabled',
      'enable_ipv6': true,
      'firewall_group_id': fwId,
      'activation_email': false,
      'tags': ['podship'],
    });
    return _server(r as Map);
  }

  @override
  Future<ProviderServer> get(String id) async =>
      _server((await _api.call('GET', '/instances/$id')) as Map);

  @override
  Future<String> destroy(String id) async {
    await _api.call('DELETE', '/instances/$id');
    return 'deleted instance $id (billing stops)';
  }

  /// For tests and dry runs: the create request bodies, without sending.
  static String describe(ServerSpec spec) =>
      const JsonEncoder.withIndent('  ').convert({
        'POST /ssh-keys': [
          for (final k in spec.sshKeys)
            {'name': spec.name, 'ssh_key': k.split(' ').take(2).join(' ')},
        ],
        'POST /firewalls': {'description': '${spec.name} (podship)'},
        'POST /firewalls/{id}/rules': [
          for (final p in spec.firewallPorts)
            {'ip_type': 'v4|v6', 'protocol': 'TCP', 'port': '$p'},
        ],
        'POST /instances': {
          'region': spec.region,
          'plan': spec.plan,
          'os_id': int.tryParse(spec.image ?? '') ?? ubuntuLts,
          'label': spec.name,
          'enable_ipv6': true,
          'backups': 'disabled',
        },
      });
}
