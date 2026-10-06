// The built-in providers. Import this file to use them.

import 'hostinger.dart';
import 'provider.dart';
import 'vultr.dart';

export 'hostinger.dart';
export 'provider.dart';
export 'vultr.dart';

/// Registers the built-in providers.
void registerBuiltInProviders() {
  registerProvider('vultr', VultrProvider.new);
  registerProvider('hostinger', HostingerProvider.new);
}

/// The request bodies [create] would send, for dry runs.
String describeCreate(String provider, ServerSpec spec) => switch (provider) {
  'vultr' => VultrProvider.describe(spec),
  'hostinger' => HostingerProvider.describe(spec),
  _ => throw ProviderException('unknown provider "$provider"'),
};
