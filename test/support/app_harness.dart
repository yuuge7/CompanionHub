import 'dart:io';

import 'package:companion_hub/data/store.dart';
import 'package:companion_hub/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Points Hive at a fresh temp directory, stubs the platform channels the app
/// touches and opens the store. Call from `setUpAll`.
///
/// Hive state is process-global and its pending futures are bound to the
/// fake-async zone of the test that started them, so keep flows that write
/// heavily in their own test file (= own isolate).
Future<void> initAppHarness() async {
  final tmp = await Directory.systemTemp.createTemp('companion_hub_test');
  PathProviderPlatform.instance = _FakePathProvider(tmp.path);

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (call) async => call.method == 'initialize' ? true : null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('x-slayer/overlay_channel'),
    (call) async => false,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('home_widget'),
    (call) async => true,
  );

  await Store.init();
  await NotificationService.instance.init();
}

/// Runs [op] from the fake-async test zone and, like the energy editor save loop,
/// alternates real-async waits (Hive file I/O) with pumps (microtasks,
/// frames) until it completes. Rethrows anything [op] throws.
Future<void> settle(WidgetTester tester, Future<void> Function() op) async {
  var done = false;
  Object? error;
  op().then((_) => done = true, onError: (Object e) {
    error = e;
    done = true;
  });
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'operation should finish');
  await tester.pump();
}
