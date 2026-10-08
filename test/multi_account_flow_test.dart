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
    expect(find.text('Main'), findsNWidgets(GameId.values.length),
        reason: 'every card is tagged, a game\'s only account included');

    // A single account shows the name it was given.
    const wuwa = Account(GameId.wuwa, Account.mainId);
    await settle(tester, () => settings.renameAccount(wuwa, 'EU main'));
    expect(find.text('EU main'), findsOneWidget);
    expect(find.text('Main'), findsNWidgets(GameId.values.length - 1));

    // Moving the WuWa card to the top puts it above the HSR accounts.
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('EU main'), greaterThan(top('Alt')));
    await settle(
        tester,
        () => settings.moveAccount(
            current().visibleAccounts.indexOf(wuwa), 0));
    expect(top('EU main'), lessThan(top('Alt')));
    expect(Store.settings().visibleAccounts.first, wuwa,
        reason: 'the card order is persisted');

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
