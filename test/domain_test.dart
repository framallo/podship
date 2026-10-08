@Tags(['unit'])
library;

import 'package:podship/src/ops/domain_ops.dart';
import 'package:podship/src/ops/resolve.dart';
import 'package:test/test.dart';

const tunnel = '''
tunnel: abc
credentials-file: /root/.cloudflared/abc.json
ingress:
  - hostname: a.com
    service: http://localhost:8087
  - hostname: old.com
    service: http://localhost:8082
  - service: http_status:404
''';

void main() {
  test('adds rules before the catch-all, paths first', () {
    final out = editTunnelConfig(tunnel, 'new.com', [
      ResolvedRoute(null, 20000),
      ResolvedRoute('^/api/', 20001),
    ]);
    final rules = tunnelRules(out);
    expect(rules, [
      'a.com → http://localhost:8087',
      'old.com → http://localhost:8082',
      'new.com ^/api/ → http://localhost:20001',
      'new.com → http://localhost:20000',
      '* → http_status:404',
    ]);
    expect(out, contains('credentials-file: /root/.cloudflared/abc.json'));
  });

  test('replaces the rules of a host in place of the old ones', () {
    final out = editTunnelConfig(tunnel, 'old.com', [
      ResolvedRoute(null, 20000),
    ]);
    expect(tunnelRules(out), contains('old.com → http://localhost:20000'));
    expect(
      tunnelRules(out),
      isNot(contains('old.com → http://localhost:8082')),
    );
    expect(tunnelRules(out).last, '* → http_status:404');
  });

  test('removes a host', () {
    final out = editTunnelConfig(tunnel, 'old.com', const []);
    expect(tunnelRules(out).where((r) => r.startsWith('old.com')), isEmpty);
  });

  test('writes a Caddy site with path routes first', () {
    final s = caddySite('demo/staging', {
      'staging.example.com': [
        ResolvedRoute('^/(api|v1)/', 20001),
        ResolvedRoute(null, 20000),
      ],
    });
    expect(s, contains('staging.example.com {'));
    expect(s, contains('@r0 path_regexp ^/(api|v1)/'));
    expect(s.indexOf('20001'), lessThan(s.indexOf('20000')));
  });
}
