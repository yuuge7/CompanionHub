import 'package:companion_hub/core/games.dart';
import 'package:companion_hub/data/models.dart';
import 'package:companion_hub/data/store.dart';
import 'package:companion_hub/main.dart';
import 'package:companion_hub/providers/providers.dart';
import 'package:companion_hub/screens/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initAppHarness);

  testWidgets('multi-account mode: extra account has its own energy',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const ProviderScope(child: CompanionHubApp()));
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final settings = container.read(settingsProvider.notifier);
    AppSettings current() => container.read(settingsProvider);

    await settle(tester,
        () => settings.update(current().copyWith(multiAccountEnabled: true)));
    await settle(tester, () => settings.addAccount(GameId.hsr, 'Alt'));

    final alt = current().accountsOf(GameId.hsr).last;
    expect(alt.label, 'Alt');
    expect(find.text('Alt'), findsOneWidget,
        reason: 'the extra account gets its own tagged card');
    expect(find.text('Main'), findsOneWidget,
        reason: 'the main account is tagged once the game has two accounts');

    await settle(tester,
        () => container.read(energyProvider.notifier).setEnergy(alt, energy: 42));
    expect(find.text('42'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(GameId.values.length),
        reason: 'every main account keeps its own (untouched) energy');

    // Turning the mode off hides the extra account but keeps its data.
    await settle(tester,
        () => settings.update(current().copyWith(multiAccountEnabled: false)));
    expect(find.text('42'), findsNothing);
    expect(find.text('Alt'), findsNothing);
    expect(Store.energy(alt).energy, 42);

    // Removing the account wipes its data.
    await settle(tester,
        () => settings.update(current().copyWith(multiAccountEnabled: true)));
    await settle(tester, () => settings.removeAccount(alt));
    expect(find.text('Alt'), findsNothing);
    expect(current().accountsOf(GameId.hsr).length, 1);
    expect(Store.energy(Account(GameId.hsr, alt.id)).energy, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
