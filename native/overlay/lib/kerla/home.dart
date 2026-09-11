import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/home.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'import_profile.dart';

class KerlaHome extends ConsumerStatefulWidget {
  const KerlaHome({super.key});
  @override
  ConsumerState<KerlaHome> createState() => _KerlaHomeState();
}

class _KerlaHomeState extends ConsumerState<KerlaHome>
    with WidgetsBindingObserver {
  final _api = KerlaApi();
  final _email = TextEditingController();
  final _code = TextEditingController();
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _catalog;
  String? _order;
  String? _requestId;
  String? _requestedPlan;
  String? _error;
  int? _pilotProfileId;
  bool _busy = false;
  bool _codeSent = false;
  bool _consent = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && _api.signedIn) unawaited(_run(_refresh));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _run(() async {
            final preferences = await SharedPreferences.getInstance();
            _pilotProfileId = preferences.getInt('kerla_pilot_profile_id');
            if (_api.configured) {
              _catalog = await _api.call('/v1/catalog');
            }
          }),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && _api.signedIn) {
      unawaited(_run(_refresh));
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } on KerlaApiException catch (error) {
      if (mounted) _error = error.message;
      if (!_api.signedIn) _account = null;
    } on FormatException {
      if (mounted) _error = 'INVALID_PROFILE';
    } catch (_) {
      if (mounted) _error = 'OPERATION_FAILED';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final expires = DateTime.tryParse(_account?['expiresAt'] as String? ?? '');
    if (expires != null && expires.isBefore(DateTime.now())) {
      await ref.read(setupActionProvider.notifier).setRunning(false);
    }
    final account = await _api.call('/v1/me');
    if (!mounted) return;
    _account = account;
    if (account['active'] != true && ref.read(isStartProvider)) {
      await ref.read(setupActionProvider.notifier).setRunning(false);
    }
  }

  Future<void> _connect() async {
    if (ref.read(isStartProvider)) {
      await ref.read(setupActionProvider.notifier).setRunning(false);
      return;
    }
    await _refresh();
    if (!mounted || _account?['active'] != true) return;
    final preferences = await SharedPreferences.getInstance();
    var installation = preferences.getString('kerla_installation');
    if (installation == null) {
      installation = KerlaApi.identifier();
      await preferences.setString('kerla_installation', installation);
    }
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isWindows
        ? 'Windows'
        : Platform.isMacOS
        ? 'macOS'
        : 'Linux';
    final device = await _api.call(
      '/v1/devices',
      method: 'POST',
      data: {
        'installation': installation,
        'name': platform,
        'platform': platform,
      },
    );
    await preferences.setString(
      'kerla_device_id',
      device['deviceId'] as String,
    );
    Map<String, dynamic>? config;
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted) return;
      try {
        config = await _api.call('/v1/devices/${device['deviceId']}/profile');
        break;
      } on KerlaApiException catch (error) {
        if (error.status != 409 || attempt == 11) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (!mounted || config == null) return;
    final savedId = preferences.getInt('kerla_profile_id');
    final existing = ref
        .read(profilesProvider)
        .where((p) => p.id == savedId)
        .firstOrNull;
    final profile = await (existing ?? Profile.normal(label: 'VPNkerla'))
        .copyWith(autoUpdate: false)
        .saveFile(
          Uint8List.fromList(utf8.encode(jsonEncode(config))),
          validate: (path) =>
              ref.read(coreHandlerProvider).validateConfig(path),
        );
    if (!mounted) return;
    ref.read(profilesProvider.notifier).put(profile);
    ref.read(currentProfileIdProvider.notifier).value = profile.id;
    await preferences.setInt('kerla_profile_id', profile.id);
    await _startProfile(profile.id);
    await _refresh();
  }

  Future<void> _startProfile(int profileId) async {
    ref.read(currentProfileIdProvider.notifier).value = profileId;
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            mode: Mode.rule,
            tun: state.tun.copyWith(enable: true),
          ),
        );
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(routeMode: RouteMode.config));
    if (!mounted) return;
    final started = await ref
        .read(setupActionProvider.notifier)
        .setRunning(true, initialize: true);
    if (!started) throw const KerlaApiException('START_FAILED');
    if (system.isDesktop &&
        ref.read(authorizedTunEnableProvider) !=
            TunAuthorizationState.authorized) {
      await ref.read(setupActionProvider.notifier).setRunning(false);
      throw const KerlaApiException('START_FAILED');
    }
  }

  Future<void> _connectPilot() async {
    if (ref.read(isStartProvider)) {
      await ref.read(setupActionProvider.notifier).setRunning(false);
      return;
    }
    final id = _pilotProfileId;
    if (id == null || !ref.read(profilesProvider).any((p) => p.id == id)) {
      throw const KerlaApiException('INVALID_PROFILE');
    }
    await _startProfile(id);
  }

  Future<void> _importPilot() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportKeyDialog(),
    );
    if (input == null || !mounted) return;
    await _run(() async {
      final config = importKerlaProfile(input);
      final existing = ref
          .read(profilesProvider)
          .where((p) => p.id == _pilotProfileId)
          .firstOrNull;
      if (existing != null &&
          ref.read(isStartProvider) &&
          ref.read(currentProfileIdProvider) == existing.id) {
        await ref.read(setupActionProvider.notifier).setRunning(false);
      }
      final profile = await (existing ?? Profile.normal(label: 'VPNkerla'))
          .copyWith(autoUpdate: false)
          .saveFile(
            Uint8List.fromList(utf8.encode(jsonEncode(config))),
            validate: (path) =>
                ref.read(coreHandlerProvider).validateConfig(path),
          );
      if (!mounted) return;
      ref.read(profilesProvider.notifier).put(profile);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt('kerla_pilot_profile_id', profile.id);
      _pilotProfileId = profile.id;
    });
  }

  Future<void> _checkout(Map<String, dynamic> plan) async {
    if (_requestedPlan != plan['id']) {
      _requestId = KerlaApi.identifier();
      _requestedPlan = plan['id'] as String;
    }
    final order = await _api.call(
      '/v1/orders',
      method: 'POST',
      data: {'planId': plan['id'], 'requestId': _requestId},
    );
    _order = order['orderId'] as String;
    final url = Uri.parse(order['url'] as String);
    if (url.scheme != 'https' ||
        !(url.host == 'yoomoney.ru' ||
            url.host.endsWith('.yoomoney.ru') ||
            url.host == 'yookassa.ru' ||
            url.host.endsWith('.yookassa.ru'))) {
      throw const KerlaApiException('INVALID_RESPONSE');
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw const KerlaApiException('OPEN_FAILED');
    }
  }

  Future<void> _logout({bool delete = false}) async {
    await ref.read(setupActionProvider.notifier).setRunning(false);
    if (delete) await _api.call('/v1/me', method: 'DELETE');
    try {
      await _api.logout();
    } finally {
      final preferences = await SharedPreferences.getInstance();
      final id = preferences.getInt('kerla_profile_id');
      if (id != null && mounted) {
        await ref.read(profilesActionProvider.notifier).deleteProfile(id);
      }
      await preferences.remove('kerla_profile_id');
      _account = null;
      _code.clear();
      _codeSent = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final running = ref.watch(isStartProvider);
    final active = _account?['active'] == true;
    final plans = (_catalog?['plans'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final devices = (_account?['devices'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final error = _error;
    final errorText = error == null
        ? null
        : error == 'API_NOT_CONFIGURED'
        ? l.kerlaNotConfigured
        : error == 'INVALID_PROFILE'
        ? l.kerlaInvalidProfile
        : [
            'NETWORK_ERROR',
            'OPERATION_FAILED',
            'START_FAILED',
            'INVALID_RESPONSE',
            'OPEN_FAILED',
          ].contains(error)
        ? l.kerlaOperationFailed
        : error;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffc5f56b),
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('VPNkerla'),
          actions: [
            IconButton(
              tooltip: l.kerlaAdvanced,
              icon: const Icon(Icons.settings_outlined),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const HomePage()),
                    ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        errorText,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_account == null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l.kerlaExistingKey,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(l.kerlaPilotHelp),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _importPilot,
                              icon: const Icon(Icons.key),
                              label: Text(l.kerlaImportKey),
                            ),
                            if (_pilotProfileId != null || running) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(_connectPilot),
                                icon: const Icon(Icons.power_settings_new),
                                label: Text(
                                  running ? l.kerlaDisconnect : l.kerlaConnect,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(running ? l.kerlaRunning : l.kerlaStopped),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_api.configured) Text(l.kerlaNotConfigured),
                    Text(
                      l.kerlaWelcome,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(l.kerlaSignInHelp),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      enabled: !_busy && !_codeSent,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    CheckboxListTile(
                      value: _consent,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _consent = value ?? false),
                      title: Text(l.kerlaConsent),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_codeSent) ...[
                      TextField(
                        controller: _code,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        decoration: InputDecoration(labelText: l.kerlaCode),
                      ),
                      FilledButton(
                        onPressed: _busy || !_consent
                            ? null
                            : () => _run(() async {
                                _account = await _api.verify(
                                  _email.text.trim(),
                                  _code.text.trim(),
                                );
                                _code.clear();
                                _catalog = await _api.call('/v1/catalog');
                              }),
                        child: Text(l.kerlaSignIn),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _codeSent = false),
                        child: Text(l.kerlaChangeEmail),
                      ),
                    ] else
                      FilledButton(
                        onPressed: _busy || !_consent || !_api.configured
                            ? null
                            : () => _run(() async {
                                await _api.call(
                                  '/v1/auth/request',
                                  method: 'POST',
                                  data: {'email': _email.text.trim()},
                                );
                                if (mounted) _codeSent = true;
                              }),
                        child: Text(l.kerlaSendCode),
                      ),
                  ] else ...[
                    Text(
                      _account!['email'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(active ? l.kerlaActive : l.kerlaNoSubscription),
                    if (_account!['expiresAt'] != null)
                      Text(
                        DateTime.parse(
                          _account!['expiresAt'] as String,
                        ).toLocal().toString().split('.').first,
                      ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _busy || (!active && !running)
                          ? null
                          : () => _run(_connect),
                      icon: const Icon(Icons.power_settings_new, size: 32),
                      label: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          running ? l.kerlaDisconnect : l.kerlaConnect,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      running ? l.kerlaRunning : l.kerlaStopped,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(l.kerlaProtocols, textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    Text(
                      l.kerlaPlans,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_catalog?['salesEnabled'] != true)
                      Text(l.kerlaSalesClosed),
                    for (final plan in plans)
                      Card(
                        child: ListTile(
                          title: Text(plan['name'] as String),
                          subtitle: Text('${(plan['amount'] as num) / 100} ₽'),
                          trailing: FilledButton(
                            onPressed:
                                _busy || _catalog?['salesEnabled'] != true
                                ? null
                                : () => _run(() => _checkout(plan)),
                            child: Text(l.kerlaBuy),
                          ),
                        ),
                      ),
                    if (_order != null)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                _account = await _api.call(
                                  '/v1/orders/$_order/refresh',
                                  method: 'POST',
                                );
                                if (_account?['active'] == true) {
                                  _requestId = null;
                                  _requestedPlan = null;
                                }
                              }),
                        child: Text(l.kerlaCheckPayment),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      '${l.kerlaDevices} (${devices.length}/3)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final device in devices)
                      ListTile(
                        title: Text(device['name'] as String),
                        subtitle: Text(
                          device['status'] == 'ready'
                              ? l.kerlaReady
                              : l.kerlaPending,
                        ),
                        trailing: IconButton(
                          tooltip: l.kerlaRemoveDevice,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(l.kerlaRemoveDevice),
                                      content: Text(l.kerlaRevokeHelp),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(l.kerlaCancel),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: Text(l.kerlaConfirm),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true || !mounted) return;
                                  await _api.call(
                                    '/v1/devices/${device['id']}',
                                    method: 'DELETE',
                                  );
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  if (prefs.getString('kerla_device_id') ==
                                      device['id']) {
                                    await prefs.remove('kerla_installation');
                                    await prefs.remove('kerla_device_id');
                                    await ref
                                        .read(setupActionProvider.notifier)
                                        .setRunning(false);
                                  }
                                  await _refresh();
                                }),
                        ),
                      ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _busy ? null : () => _run(_logout),
                      child: Text(l.kerlaLogout),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(l.kerlaDeleteAccount),
                                  content: Text(l.kerlaDeleteHelp),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text(l.kerlaCancel),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text(l.kerlaConfirm),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                await _logout(delete: true);
                              }
                            }),
                      child: Text(l.kerlaDeleteAccount),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(l.kerlaAvailability),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'VPNkerla',
                      applicationLegalese:
                          'Based on FlClash and mihomo · GPL-3.0\nhttps://github.com/chen08209/FlClash',
                    ),
                    child: Text(l.kerlaLicenses),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _api.close();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }
}

class _ImportKeyDialog extends StatefulWidget {
  const _ImportKeyDialog();

  @override
  State<_ImportKeyDialog> createState() => _ImportKeyDialogState();
}

class _ImportKeyDialogState extends State<_ImportKeyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return AlertDialog(
      title: Text(l.kerlaImportKey),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        maxLength: 65536,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(helperText: l.kerlaKeyHelp),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.kerlaCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l.kerlaImportKey),
        ),
      ],
    );
  }
}
