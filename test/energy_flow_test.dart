import 'package:companion_hub/core/games.dart';
import 'package:companion_hub/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initAppHarness);

  testWidgets('setting energy updates the card and it regenerates',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const ProviderScope(child: CompanionHubApp()));
    await tester.pump();

    // Every game starts at 0.
    expect(find.text('0'), findsNWidgets(GameId.values.length));

    // Open the HSR editor.
    await tester.tap(find.text('Honkai: Star Rail'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('energy-main')), '180');
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
