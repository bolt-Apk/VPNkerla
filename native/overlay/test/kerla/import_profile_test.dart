import 'package:fl_clash/kerla/import_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '00000000-0000-4000-8000-000000000001';
  final publicKey = List.filled(43, 'A').join();
  final reality =
      'vless://$id@vpn.example:443?security=reality&type=tcp&pbk=$publicKey&sid=abcdef12&sni=front.example&flow=xtls-rprx-vision';

  test('imports issued REALITY values without a direct fallback', () {
    final config = importKerlaProfile(reality);
    final proxy = (config['proxies'] as List).single as Map;
    expect(proxy['uuid'], id);
    expect(proxy['servername'], 'front.example');
    expect(proxy['reality-opts'], {
      'public-key': publicKey,
      'short-id': 'abcdef12',
    });
    expect(config['rules'], ['MATCH,VPNkerla']);
    expect(
      (config['proxy-groups'] as List).every(
        (g) => !(g['proxies'] as List).contains('DIRECT'),
      ),
      isTrue,
    );
  });

  test('preserves XHTTP path, authority and TLS verification', () {
    final config = importKerlaProfile(
      'vless://$id@vpn.example:8443?security=tls&type=xhttp&path=%2Fsession%2F&host=edge.example&sni=cert.example',
    );
    final proxy = (config['proxies'] as List).single as Map;
    expect(proxy['xhttp-opts'], {
      'path': '/session/',
      'host': 'edge.example',
      'mode': 'auto',
    });
    expect(proxy['servername'], 'cert.example');
    expect(proxy['tls'], isTrue);
    expect(proxy['skip-cert-verify'], isNot(true));
  });

  test('decodes Hysteria password and preserves certificate verification', () {
    final config = importKerlaProfile(
      'hysteria2://pass%3Aword@vpn.example:443?sni=cert.example',
    );
    final proxy = (config['proxies'] as List).single as Map;
    expect(proxy['password'], 'pass:word');
    expect(proxy['skip-cert-verify'], isFalse);
  });

  test(
    'rejects unsupported or insecure input rather than silently changing it',
    () {
      for (final value in [
        '',
        'https://example.com',
        '$reality&insecure=1',
        'vless://$id@vpn.example:443?security=none&type=tcp',
        'vless://$id@vpn.example:443?security=reality&type=tcp&pbk=bad',
        'hy2://key@vpn.example:443?obfs=unknown',
      ]) {
        expect(() => importKerlaProfile(value), throwsFormatException);
      }
    },
  );

  test('combines multiple keys into independent fallback choices', () {
    final config = importKerlaProfile(
      '$reality\nhy2://secret@vpn.example:443?sni=cert.example',
    );
    final groups = config['proxy-groups'] as List;
    expect((config['proxies'] as List).length, 2);
    expect(groups.last['proxies'], ['VPNkerla 1', 'VPNkerla 2']);
    expect(groups.last['type'], 'fallback');
  });
}
