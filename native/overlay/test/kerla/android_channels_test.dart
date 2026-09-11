import 'dart:io';

import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _android = 'android/app/src/main/kotlin/com/follow/clash';

String _nativeChannel(String plugin) {
  final source = File(
    '$_android/plugins/${plugin}Plugin.kt',
  ).readAsStringSync();
  final channel = RegExp(
    r'"\$\{Components\.(\w+)\}/(\w+)"',
  ).firstMatch(source)!;
  final components = File(
    'android/common/src/main/java/com/follow/clash/common/Components.kt',
  ).readAsStringSync();
  final namespace = RegExp(
    'const val ${channel[1]} = "([^"]+)"',
  ).firstMatch(components)![1];
  return '$namespace/${channel[2]}';
}

class _TileEvents with TileListener {
  int starts = 0;

  @override
  void onStart() => starts++;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  test('service init reaches the channel registered by Android', () async {
    final channel = MethodChannel(_nativeChannel('Service'));
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return '';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await Service().init(), isEmpty);
    expect(methods, ['init']);
  });

  test(
    'app permission calls reach the channel registered by Android',
    () async {
      final channel = MethodChannel(_nativeChannel('App'));
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await App().requestNotificationsPermission(), isTrue);
      expect(methods, ['requestNotificationsPermission']);
    },
  );

  test('quick settings events reach Dart from the Android channel', () async {
    final listener = _TileEvents();
    Tile.instance.addListener(listener);
    addTearDown(() => Tile.instance.removeListener(listener));
    await messenger.handlePlatformMessage(
      _nativeChannel('Tile'),
      const StandardMethodCodec().encodeMethodCall(const MethodCall('start')),
      (_) {},
    );
    expect(listener.starts, 1);
  });

  test('main engine registers each native plugin', () {
    final activity = File('$_android/MainActivity.kt').readAsStringSync();
    for (final plugin in ['Service', 'App', 'Tile']) {
      expect(
        activity,
        contains('flutterEngine.plugins.add(${plugin}Plugin())'),
      );
    }
  });
}
