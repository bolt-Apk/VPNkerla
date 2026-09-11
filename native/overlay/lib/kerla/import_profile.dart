Map<String, dynamic> importKerlaProfile(String input) {
  if (input.length > 65536) throw const FormatException('INVALID_PROFILE');
  final lines = input.trim().split(RegExp(r'\s+'));
  if (lines.isEmpty || lines.length > 20) {
    throw const FormatException('INVALID_PROFILE');
  }
  final proxies = <Map<String, dynamic>>[];
  for (final line in lines) {
    final uri = Uri.tryParse(line);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('INVALID_PROFILE');
    }
    final q = uri.queryParameters;
    if (q['insecure'] == '1' || q['allowInsecure'] == '1') {
      throw const FormatException('INSECURE_PROFILE');
    }
    final name = 'VPNkerla ${proxies.length + 1}';
    final credential = Uri.decodeComponent(uri.userInfo);
    final serverName = q['sni'] ?? q['peer'] ?? uri.host;
    final base = <String, dynamic>{
      'name': name,
      'server': uri.host,
      'port': uri.port,
    };
    if (uri.scheme == 'vless') {
      if (!RegExp(
        r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
      ).hasMatch(credential)) {
        throw const FormatException('INVALID_PROFILE');
      }
      final transport = q['type'] ?? 'tcp';
      base.addAll({
        'type': 'vless',
        'uuid': credential,
        'udp': true,
        'tls': true,
        'servername': serverName,
        'client-fingerprint': q['fp'] ?? 'chrome',
      });
      if (q['security'] == 'reality' && ['tcp', 'raw'].contains(transport)) {
        final key = q['pbk'] ?? '';
        final shortId = q['sid'] ?? '';
        if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(key) ||
            !RegExp(r'^(?:[0-9a-fA-F]{2}){0,8}$').hasMatch(shortId) ||
            !['', 'xtls-rprx-vision'].contains(q['flow'] ?? '')) {
          throw const FormatException('INVALID_PROFILE');
        }
        base.addAll({
          'network': 'tcp',
          if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
          'reality-opts': {'public-key': key, 'short-id': shortId},
        });
      } else if (q['security'] == 'tls' && transport == 'xhttp') {
        final path = q['path'] ?? '/';
        final mode = q['mode'] ?? 'auto';
        if (!path.startsWith('/') ||
            !['auto', 'packet-up', 'stream-up', 'stream-one'].contains(mode) ||
            (q['flow'] ?? '').isNotEmpty) {
          throw const FormatException('INVALID_PROFILE');
        }
        base.addAll({
          'network': 'xhttp',
          'xhttp-opts': {
            'path': path,
            'host': q['host'] ?? serverName,
            'mode': mode,
          },
        });
      } else {
        throw const FormatException('UNSUPPORTED_PROFILE');
      }
    } else if (['hysteria2', 'hy2'].contains(uri.scheme)) {
      base.addAll({
        'type': 'hysteria2',
        'password': credential,
        'sni': serverName,
        'skip-cert-verify': false,
      });
      if (q.containsKey('obfs')) {
        if (q['obfs'] != 'salamander' || (q['obfs-password'] ?? '').isEmpty) {
          throw const FormatException('INVALID_PROFILE');
        }
        base.addAll({
          'obfs': 'salamander',
          'obfs-password': q['obfs-password'],
        });
      }
    } else {
      throw const FormatException('UNSUPPORTED_PROFILE');
    }
    proxies.add(base);
  }
  final names = proxies.map((p) => p['name'] as String).toList();
  return {
    'mixed-port': 7890,
    'allow-lan': false,
    'bind-address': '127.0.0.1',
    'mode': 'rule',
    'log-level': 'warning',
    'ipv6': false,
    'tun': {
      'enable': true,
      'stack': 'mixed',
      'auto-route': true,
      'auto-detect-interface': true,
      'strict-route': true,
      'dns-hijack': ['any:53'],
    },
    'dns': {
      'enable': true,
      'ipv6': false,
      'enhanced-mode': 'fake-ip',
      'respect-rules': true,
      'default-nameserver': ['1.1.1.1'],
      'proxy-server-nameserver': ['https://1.1.1.1/dns-query'],
      'nameserver': ['https://1.1.1.1/dns-query'],
    },
    'proxies': proxies,
    'proxy-groups': [
      {
        'name': 'VPNkerla',
        'type': 'select',
        'proxies': ['Auto', ...names],
      },
      {
        'name': 'Auto',
        'type': 'fallback',
        'proxies': names,
        'url': 'https://www.gstatic.com/generate_204',
        'interval': 60,
        'lazy': false,
      },
    ],
    'rules': ['MATCH,VPNkerla'],
  };
}
