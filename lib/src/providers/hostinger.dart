// Hostinger (developers.hostinger.com). No location in Mexico.
//
// Creating a VPS is a purchase: it charges the account's default payment
// method. Hostinger's API has no "delete VM": `destroy` turns off the
// subscription's auto-renewal, and the VPS runs until it expires.

import 'dart:convert';

import 'provider.dart';

class HostingerProvider extends ServerProvider {
  HostingerProvider(String token)
    : _api = JsonApi('https://developers.hostinger.com', token);
  final JsonApi _api;

  @override
  String get name => 'hostinger';

  @override
  Future<List<ProviderOffer>> offers() async {
    final dcs = (await _api.call('GET', '/api/vps/v1/data-centers')) as List;
    final catalog =
        (await _api.call('GET', '/api/billing/v1/catalog?category=VPS'))
            as List;
    final plans = <String, num>{
      for (final item in catalog.cast<Map>())
        for (final p in (item['prices'] as List).cast<Map>())
          if (p['period'] == 1 && p['period_unit'] == 'month')
            '${p['id']}': (p['price'] as num) / 100,
    };
    return [
      for (final d in dcs.cast<Map>())
        ProviderOffer('${d['id']}', '${d['city']}', '${d['location']}', plans),
    ];
  }

  Future<int> _ubuntuTemplate() async {
    final t = (await _api.call('GET', '/api/vps/v1/templates')) as List;
    final ubuntu =
        t
            .cast<Map>()
            .where(
              (x) =>
                  '${x['name']}'.startsWith('Ubuntu') &&
                  '${x['name']}'.contains('LTS'),
            )
            .toList()
          ..sort((a, b) => '${b['name']}'.compareTo('${a['name']}'));
    if (ubuntu.isEmpty) {
      throw ProviderException('no Ubuntu LTS template at Hostinger');
    }
    return ubuntu.first['id'] as int;
  }

  ProviderServer _server(Map vm) {
    final v4 = vm['ipv4'] is List && (vm['ipv4'] as List).isNotEmpty
        ? '${((vm['ipv4'] as List).first as Map)['address']}'
        : null;
    final v6 = vm['ipv6'] is List && (vm['ipv6'] as List).isNotEmpty
        ? '${((vm['ipv6'] as List).first as Map)['address']}'
        : null;
    return ProviderServer(
      id: '${vm['id']}',
      name: '${vm['hostname']}',
      status: vm['state'] == 'running' ? 'ready' : '${vm['state']}',
      ipv4: v4,
      ipv6: v6,
      region: '${vm['data_center_id']}',
      plan: '${vm['plan']}',
    );
  }

  @override
  Future<ProviderServer> create(ServerSpec spec) async {
    final template = int.tryParse(spec.image ?? '') ?? await _ubuntuTemplate();
    final r =
        (await _api.call('POST', '/api/vps/v1/virtual-machines', {
              'item_id': spec.plan,
              'setup': {
                'template_id': template,
                'data_center_id': int.parse(spec.region),
                'hostname': spec.name,
                if (spec.sshKeys.isNotEmpty)
                  'public_key': {
                    'name': '${spec.name}-podship',
                    'key': spec.sshKeys.first.trim(),
                  },
              },
            }))
            as Map;
    final vm = r['virtual_machine'] as Map;
    final id = vm['id'];
    for (final (n, k) in spec.sshKeys.skip(1).indexed) {
      final key =
          (await _api.call('POST', '/api/vps/v1/public-keys', {
                'name': '${spec.name}-podship-${n + 1}',
                'key': k.trim(),
              }))
              as Map;
      await _api.call('POST', '/api/vps/v1/public-keys/attach/$id', {
        'ids': [key['id']],
      });
    }
    final fw =
        (await _api.call('POST', '/api/vps/v1/firewall', {
              'name': '${spec.name}-podship',
            }))
            as Map;
    await _api.call('PUT', '/api/vps/v1/firewall/${fw['id']}/rules', {
      'rules': [
        for (final p in spec.firewallPorts)
          {
            'protocol': 'TCP',
            'port': '$p',
            'source': 'any',
            'source_detail': 'any',
          },
      ],
      'sync': true,
    });
    await _api.call('POST', '/api/vps/v1/firewall/${fw['id']}/activate/$id');
    return _server(vm);
  }

  @override
  Future<ProviderServer> get(String id) async => _server(
    (await _api.call('GET', '/api/vps/v1/virtual-machines/$id')) as Map,
  );

  @override
  Future<String> destroy(String id) async {
    final vm =
        (await _api.call('GET', '/api/vps/v1/virtual-machines/$id')) as Map;
    final sub = vm['subscription_id'];
    await _api.call(
      'DELETE',
      '/api/billing/v1/subscriptions/$sub/auto-renewal/disable',
    );
    return 'turned off auto-renewal of subscription $sub; Hostinger has no API to delete a VPS now, it stops when the term ends (cancel early in hPanel)';
  }

  static String describe(ServerSpec spec) =>
      const JsonEncoder.withIndent('  ').convert({
        'POST /api/vps/v1/virtual-machines': {
          'item_id': spec.plan,
          'setup': {
            'template_id': spec.image ?? '(newest Ubuntu LTS)',
            'data_center_id': spec.region,
            'hostname': spec.name,
          },
        },
        'POST /api/vps/v1/firewall': {
          'name': '${spec.name}-podship',
          'ports': spec.firewallPorts,
        },
      });
}
