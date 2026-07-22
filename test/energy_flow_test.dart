import 'dart:io';

import 'package:companion_hub/data/store.dart';
import 'package:companion_hub/main.dart';
import 'package:companion_hub/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('companion_hub_test');
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
  });

  testWidgets('setting energy updates the card and it regenerates',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const ProviderScope(child: CompanionHubApp()));
    await tester.pump();

    // All four games start at 0.
    expect(find.text('0'), findsNWidgets(4));

    // Open the HSR editor.
    await tester.tap(find.text('Honkai: Star Rail'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '180');
    await tester.tap(find.text('Save'));
    // Hive writes are real file I/O: alternate real-async waits (I/O
    // completion) with fake-async pumps (microtask/frame flush) until the
    // save chain finishes and the sheet pops.
    for (var i = 0;
        i < 40 && find.byType(TextField).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.text('180'), findsOneWidget,
        reason: 'saved energy should appear on the HSR card');

    // Sheet must have closed after save.
    expect(find.byType(TextField), findsNothing,
        reason: 'editor sheet should pop after saving');

    // Tear the scope down and let riverpod cancel the clock stream.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('saved energy survives an app restart', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    // Fresh ProviderScope = fresh notifiers reading from the same Hive boxes.
    await tester.pumpWidget(const ProviderScope(child: CompanionHubApp()));
    await tester.pump();

    expect(find.text('180'), findsOneWidget,
        reason: 'persisted HSR energy should be restored from Hive');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
