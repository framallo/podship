// Server providers: create and delete servers through a provider's API.
//
// A provider is a plugin: implement [ServerProvider] and add it to
// [providers]. Tokens come from the user's secret store (see
// [ProviderTokens]), never from podship.yaml.
//
// Which providers have a location in Mexico (October 2026):
//   Vultr         yes   mex (Mexico City)
//   AWS EC2       yes   mx-central-1 (Querétaro)
//   Google Cloud  yes   northamerica-south1 (Querétaro)
//   Azure         yes   Mexico Central (Querétaro)
//   Oracle Cloud  yes   Querétaro, Monterrey
//   Hostinger     no    (closest: Phoenix, São Paulo)
//   AWS Lightsail no
//   DigitalOcean  no
//   Hetzner       no
//   Linode/Akamai only a contact-sales distributed location in Querétaro

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What to create.
class ServerSpec {
  ServerSpec({
    required this.name,
    required this.region,
    required this.plan,
    this.image,
    this.sshKeys = const [],
    this.firewallPorts = const [22, 80, 443],
  });

  /// A label and host name.
  final String name;

  /// The provider's region or data center (`mex` at Vultr).
  final String region;

  /// The provider's plan (`vc2-2c-4gb` at Vultr, a price id at Hostinger).
  final String plan;

  /// The OS image; default: the provider's newest Ubuntu LTS.
  final String? image;

  /// Public keys for root.
  final List<String> sshKeys;

  /// Inbound TCP ports the provider firewall allows.
  final List<int> firewallPorts;

  Map<String, Object?> toJson() => {
    'name': name,
    'region': region,
    'plan': plan,
    'image': ?image,
    'ssh_keys': [for (final k in sshKeys) k.split(' ').take(2).join(' ')],
    'firewall_ports': firewallPorts,
  };
}

/// A server at a provider.
class ProviderServer {
  ProviderServer({
    required this.id,
    required this.name,
    required this.status,
    this.ipv4,
    this.ipv6,
    this.region,
    this.plan,
  });
  final String id;
  final String name;
  final String status;
  final String? ipv4;
  final String? ipv6;
  final String? region;
  final String? plan;

  /// Ready for ssh.
  bool get ready => status == 'ready' && (ipv4 != null || ipv6 != null);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'status': status,
    'ipv4': ?ipv4,
    'ipv6': ?ipv6,
    'region': ?region,
    'plan': ?plan,
  };
}

/// A region with its plans and prices, for choosing.
class ProviderOffer {
  ProviderOffer(this.region, this.city, this.country, this.plans);
  final String region;
  final String city;
  final String country;

  /// Plan id → monthly price in USD.
  final Map<String, num> plans;
  Map<String, Object?> toJson() => {
    'region': region,
    'city': city,
    'country': country,
    'plans': plans,
  };
}

class ProviderException implements Exception {
  ProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class ServerProvider {
  /// The stable name, like `vultr`.
  String get name;

  /// Regions with plans and prices.
  Future<List<ProviderOffer>> offers();

  /// Creates a server. It costs money: callers must have the user's go-ahead.
  Future<ProviderServer> create(ServerSpec spec);

  Future<ProviderServer> get(String id);

  /// Deletes (or, where the provider has no delete, stops renewing) a server.
  Future<String> destroy(String id);

  /// Waits until the server is ready for ssh.
  Future<ProviderServer> waitReady(
    String id, {
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      final s = await get(id);
      if (s.ready) return s;
      if (DateTime.now().isAfter(end))
        throw ProviderException(
          'server $id is not ready after ${timeout.inMinutes} min (status ${s.status})',
        );
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  }
}

/// A small JSON client.
class JsonApi {
  JsonApi(this.base, this.token);
  final String base;
  final String token;

  Future<Object?> call(String method, String path, [Object? body]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) {
        throw ProviderException(
          '$method $path: ${res.statusCode} ${text.length > 300 ? text.substring(0, 300) : text}',
        );
      }
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  /// A public GET without a token.
  static Future<Object?> publicGet(String url) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      return jsonDecode(await res.transform(utf8.decoder).join());
    } finally {
      client.close(force: true);
    }
  }
}

/// The provider [name] with its token.
ServerProvider providerFor(String name, String token) => switch (name) {
  'vultr' => _vultr(token),
  'hostinger' => _hostinger(token),
  _ => throw ProviderException(
    'unknown provider "$name" (known: vultr, hostinger)',
  ),
};

/// Plugins register here.
ServerProvider Function(String token) _vultr = (_) =>
    throw StateError('vultr not loaded');
ServerProvider Function(String token) _hostinger = (_) =>
    throw StateError('hostinger not loaded');

void registerProvider(String name, ServerProvider Function(String token) make) {
  switch (name) {
    case 'vultr':
      _vultr = make;
    case 'hostinger':
      _hostinger = make;
  }
}
