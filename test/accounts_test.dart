import 'package:companion_hub/core/energy_math.dart';
import 'package:companion_hub/core/games.dart';
import 'package:companion_hub/core/pity_math.dart';
import 'package:companion_hub/data/models.dart';
import 'package:companion_hub/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('account keys', () {
    test('main account keeps the pre-multi-account storage key', () {
      expect(accountKey(GameId.hsr, Account.mainId), 'hsr');
      expect(const Account(GameId.nte, Account.mainId).key, 'nte');
    });

    test('extra accounts get distinct keys', () {
      expect(accountKey(GameId.hsr, 1), 'hsr@1');
      expect(const Account(GameId.genshin, 3).key, 'genshin@3');
    });

    test('identity ignores the name', () {
      expect(
        const Account(GameId.hsr, 1, 'Alt'),
        const Account(GameId.hsr, 1, 'EU'),
      );
      expect(
        const Account(GameId.hsr, 1) == const Account(GameId.wuwa, 1),
        isFalse,
      );
    });

    test('default labels', () {
      expect(const Account(GameId.hsr, 0).label, 'Main');
      expect(const Account(GameId.hsr, 2).label, 'Account 3');
      expect(const Account(GameId.hsr, 2, 'Alt').label, 'Alt');
    });
  });

  group('account roster', () {
    const base = AppSettings();

    test('every game starts with only its main account', () {
      for (final g in GameId.values) {
        expect(base.accountsOf(g), [Account(g, Account.mainId)]);
      }
      expect(base.visibleAccounts.length, GameId.values.length);
    });

    test('adding assigns increasing ids per game', () {
      final s = base
          .withAccountAdded(GameId.hsr, ' Alt ')
          .withAccountAdded(GameId.hsr, '')
          .withAccountAdded(GameId.wuwa, 'EU');
      expect(s.accountsOf(GameId.hsr).map((a) => a.id), [0, 1, 2]);
      expect(s.accountsOf(GameId.hsr)[1].name, 'Alt');
      expect(s.accountsOf(GameId.wuwa).map((a) => a.id), [0, 1]);
    });

    test('ids are never reused after a removal', () {
      var s = base
          .withAccountAdded(GameId.hsr, 'A')
          .withAccountAdded(GameId.hsr, 'B');
      s = s.withAccountRemoved(s.accountsOf(GameId.hsr).last);
      s = s.withAccountAdded(GameId.hsr, 'C');
      expect(s.accountsOf(GameId.hsr).map((a) => a.id), [0, 1, 3]);
      final back = AppSettings.fromJson(s.toJson());
      expect(
        back.withAccountAdded(GameId.hsr, 'D').accountsOf(GameId.hsr).last.id,
        4,
        reason: 'the high-water mark survives a restart',
      );
    });

    test('empty names default to the position when added', () {
      final s = base
          .withAccountAdded(GameId.hsr, '')
          .withAccountAdded(GameId.hsr, '  ');
      expect(s.accountsOf(GameId.hsr).map((a) => a.label), [
        'Main',
        'Account 2',
        'Account 3',
      ]);
      final cleared = s.withAccountRenamed(s.accountsOf(GameId.hsr)[1], '');
      expect(cleared.accountsOf(GameId.hsr)[1].label, 'Account 2');
    });

    test('renaming a removed account does not bring it back', () {
      final s = base.withAccountAdded(GameId.hsr, 'Alt');
      final alt = s.accountsOf(GameId.hsr).last;
      final removed = s.withAccountRemoved(alt);
      expect(removed.withAccountRenamed(alt, 'Ghost').accountsOf(GameId.hsr), [
        const Account(GameId.hsr, 0),
      ]);
    });

    test('labels are appended only when a game has several accounts', () {
      final s = base
          .withAccountAdded(GameId.hsr, 'Alt')
          .copyWith(multiAccountEnabled: true);
      expect(s.withAccountLabel('HSR', GameId.hsr, 1), 'HSR · Alt');
      expect(s.withAccountLabel('HSR', GameId.hsr, 0), 'HSR · Main');
      expect(s.withAccountLabel('WuWa', GameId.wuwa, 0), 'WuWa');
    });

    test('extras are inactive while multi-account mode is off', () {
      final s = base.withAccountAdded(GameId.hsr, 'Alt');
      expect(s.activeAccountsOf(GameId.hsr).length, 1);
      expect(s.isAccountActive(GameId.hsr, 1), isFalse);
      expect(s.showsAccountLabels(GameId.hsr), isFalse);
      expect(
        s.allAccounts.length,
        GameId.values.length + 1,
        reason: 'paused accounts still load so their data is kept',
      );

      final on = s.copyWith(multiAccountEnabled: true);
      expect(on.isAccountActive(GameId.hsr, 1), isTrue);
      expect(on.showsAccountLabels(GameId.hsr), isTrue);
      expect(on.showsAccountLabels(GameId.wuwa), isFalse);
      expect(on.visibleAccounts.length, GameId.values.length + 1);
    });

    test('hidden games deactivate all their accounts', () {
      final s = base
          .withAccountAdded(GameId.hsr, 'Alt')
          .copyWith(multiAccountEnabled: true, hiddenGames: {GameId.hsr});
      expect(s.isAccountActive(GameId.hsr, 0), isFalse);
      expect(s.isAccountActive(GameId.hsr, 1), isFalse);
      expect(s.visibleAccounts.any((a) => a.game == GameId.hsr), isFalse);
    });

    test('renaming the main account keeps it first and unique', () {
      final s = base
          .withAccountAdded(GameId.hsr, 'Alt')
          .withAccountRenamed(const Account(GameId.hsr, 0), 'Asia');
      final accounts = s.accountsOf(GameId.hsr);
      expect(accounts.map((a) => a.label), ['Asia', 'Alt']);
    });

    test('roster key ignores renames but tracks adds/removes', () {
      final s = base.withAccountAdded(GameId.hsr, 'Alt');
      final alt = s.accountsOf(GameId.hsr).last;
      expect(s.withAccountRenamed(alt, 'EU').rosterKey, s.rosterKey);
      expect(s.withAccountRemoved(alt).rosterKey, base.rosterKey);
      expect(s.rosterKey, isNot(base.rosterKey));
    });

    test('widget account falls back to main when removed or paused', () {
      var s = base
          .withAccountAdded(GameId.hsr, 'Alt')
          .copyWith(multiAccountEnabled: true);
      final alt = s.accountsOf(GameId.hsr).last;
      s = s.withWidgetAccount(alt);
      expect(s.widgetAccountOf(GameId.hsr), alt);
      expect(
        s
            .copyWith(multiAccountEnabled: false)
            .widgetAccountOf(GameId.hsr)
            .isMain,
        isTrue,
      );
      final removed = s.withAccountRemoved(alt);
      expect(removed.widgetAccountOf(GameId.hsr).isMain, isTrue);
      expect(removed.widgetAccounts.containsKey(GameId.hsr), isFalse);
    });

    test('JSON round trip keeps accounts and widget choice', () {
      var s = base
          .withAccountAdded(GameId.genshin, 'EU')
          .copyWith(multiAccountEnabled: true);
      s = s.withWidgetAccount(s.accountsOf(GameId.genshin).last);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.multiAccountEnabled, isTrue);
      expect(back.accountsOf(GameId.genshin).map((a) => a.label), [
        'Main',
        'EU',
      ]);
      expect(back.widgetAccountOf(GameId.genshin).id, 1);
    });

    test('settings saved before multi-account mode still load', () {
      final old = AppSettings.fromJson({
        'notificationsEnabled': true,
        'hiddenGames': ['nte'],
      });
      expect(old.multiAccountEnabled, isFalse);
      expect(old.accounts, isEmpty);
      expect(old.isHidden(GameId.nte), isTrue);
    });
  });

  group('energy anchors', () {
    const hsrMain = Account(GameId.hsr, Account.mainId);
    const nteMain = Account(GameId.nte, Account.mainId);

    test('legacy combined value splits into main pool + reserve', () {
      final st = EnergyState.fromJson(
          hsrMain, {'energy': 2000, 'updatedAtMs': 0});
      expect(st.energy, 300);
      expect(st.reserve, 1700);
    });

    test('legacy value below cap stays in the main pool', () {
      final st =
          EnergyState.fromJson(hsrMain, {'energy': 120, 'updatedAtMs': 0});
      expect(st.energy, 120);
      expect(st.reserve, 0);
    });

    test('new anchors keep an overfilled main pool as-is', () {
      final st = EnergyState.fromJson(
          hsrMain, {'energy': 420, 'reserve': 30, 'updatedAtMs': 0});
      expect(st.energy, 420);
      expect(st.reserve, 30);
    });

    test('unlocked cap round-trips; unknown caps fall back to the default',
        () {
      final st = EnergyState.fromJson(nteMain,
          {'energy': 10, 'cap': 330, 'updatedAtMs': 0});
      expect(st.effectiveCap, 330);
      expect(EnergyState.fromJson(nteMain, st.toJson()).effectiveCap, 330);
      expect(
          EnergyState.fromJson(
                  nteMain, {'energy': 10, 'cap': 999, 'updatedAtMs': 0})
              .effectiveCap,
          240);
    });
  });

  group('notification ids', () {
    test('main accounts keep their original ids', () {
      for (final g in GameId.values) {
        expect(NotificationService.capWarnId(g.index), 100 + g.index);
        expect(NotificationService.summaryId(g.index), 200 + g.index);
      }
    });

    test('no collisions across games, accounts and alert kinds', () {
      final ids = <int>{NotificationService.burnWarningId};
      var count = 1;
      for (final g in GameId.values) {
        for (var id = 0; id < kMaxAccountsPerGame; id++) {
          ids.add(NotificationService.capWarnId(g.index, id));
          ids.add(NotificationService.summaryId(g.index, id));
          count += 2;
        }
      }
      expect(ids.length, count);
    });
  });

  group('Genshin Impact', () {
    final gi = GameId.genshin.config;
    final t0 = DateTime(2026, 7, 1, 12, 0);
    EnergySnapshot at(int energy, Duration elapsed) => projectEnergy(gi,
        energy: energy, anchorTime: t0, now: t0.add(elapsed));

    test('Original Resin regenerates 1 per 8 minutes up to 200', () {
      expect(at(100, const Duration(hours: 4)).current, 130);
      final full = at(199, const Duration(days: 1));
      expect(full.current, 200);
      expect(full.wasting, isTrue);
      expect(gi.hasReserve, isFalse);
    });

    test('cap ETA matches regen math', () {
      expect(at(160, Duration.zero).capAt,
          t0.add(const Duration(minutes: 320)));
    });

    test('pity: 90 hard pity with a 50/50', () {
      expect(ratePerPull(gi, 90), 1.0);
      expect(worstCasePulls(gi, 0, false), 180);
      expect(chanceOfFeatured(gi, 0, true, 90), closeTo(1.0, 1e-9));
    });
  });
}
