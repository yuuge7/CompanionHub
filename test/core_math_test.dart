import 'package:companion_hub/core/energy_math.dart';
import 'package:companion_hub/core/games.dart';
import 'package:companion_hub/core/pity_math.dart';
import 'package:companion_hub/core/reset_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('energy projection', () {
    final hsr = GameId.hsr.config;
    final wuwa = GameId.wuwa.config;
    final re = GameId.re1999.config;
    final t0 = DateTime(2026, 7, 1, 12, 0);

    test('normal regen: 1 per 6 minutes', () {
      final snap = projectEnergy(hsr, 100, t0, t0.add(const Duration(hours: 1)));
      expect(snap.current, 110);
    });

    test('caps at normal cap then switches to overflow rate', () {
      // 10 below cap -> 60 min to cap, then 3h at 1/18min = 10 overflow.
      final snap = projectEnergy(
          hsr, 290, t0, t0.add(const Duration(hours: 4)));
      expect(snap.normalPortion, 300);
      expect(snap.overflowPortion, 10);
    });

    test('WuWa overflow rate is 1 per 12 minutes up to 480', () {
      final snap = projectEnergy(
          wuwa, 240, t0, t0.add(const Duration(hours: 2)));
      expect(snap.current, 250);
      final full = projectEnergy(wuwa, 240, t0, t0.add(const Duration(days: 3)));
      expect(full.current, 480);
      expect(full.atAbsoluteCap, isTrue);
    });

    test('no-overflow game stops at cap', () {
      final snap = projectEnergy(re, 239, t0, t0.add(const Duration(days: 1)));
      expect(snap.current, 240);
      expect(snap.absoluteCapAt, isNull);
    });

    test('cap ETA matches regen math', () {
      final snap = projectEnergy(hsr, 240, t0, t0);
      expect(snap.normalCapAt, t0.add(const Duration(minutes: 360)));
    });
  });

  group('pity math', () {
    final hsr = GameId.hsr.config;
    final nte = GameId.nte.config;

    test('hard pity forces 100%', () {
      expect(ratePerPull(hsr, 90), 1.0);
      expect(chanceOfFeatured(hsr, 89, true, 1), closeTo(1.0, 1e-9));
    });

    test('distribution sums to 1 over the full pity window', () {
      final dist = firstTopRarityDistribution(hsr, 0);
      final sum = dist.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('guaranteed beats 50/50 for same pulls', () {
      final coinFlip = chanceOfFeatured(hsr, 0, false, 90);
      final guaranteed = chanceOfFeatured(hsr, 0, true, 90);
      expect(guaranteed, greaterThan(coinFlip));
      expect(guaranteed, closeTo(1.0, 1e-9));
    });

    test('NTE has no 50/50: hard pity pulls always secure the character', () {
      expect(chanceOfFeatured(nte, 0, false, 90), closeTo(1.0, 1e-9));
      expect(worstCasePulls(nte, 30, false), 60);
    });

    test('HSR worst case without guarantee is two full pities', () {
      expect(worstCasePulls(hsr, 10, false), 80 + 90);
    });

    test('probability grows with pulls', () {
      final p30 = chanceOfFeatured(hsr, 0, false, 30);
      final p80 = chanceOfFeatured(hsr, 0, false, 80);
      expect(p80, greaterThan(p30));
    });
  });

  group('reset times', () {
    test('daily reset before/after the boundary', () {
      final before = DateTime(2026, 7, 10, 3, 0);
      final after = DateTime(2026, 7, 10, 6, 0);
      expect(lastDailyReset(4, before), DateTime(2026, 7, 9, 4));
      expect(lastDailyReset(4, after), DateTime(2026, 7, 10, 4));
    });

    test('NTE weekly reset anchors to Monday 05:00', () {
      // 2026-07-10 is a Friday.
      final now = DateTime(2026, 7, 10, 12, 0);
      expect(lastWeeklyReset(DateTime.monday, 5, now), DateTime(2026, 7, 6, 5));
      expect(nextWeeklyReset(DateTime.monday, 5, now), DateTime(2026, 7, 13, 5));
    });

    test('burn warning slot is the upcoming Sunday evening', () {
      final now = DateTime(2026, 7, 10, 12, 0);
      expect(nextWeekdayTime(DateTime.sunday, 19, now),
          DateTime(2026, 7, 12, 19));
    });
  });
}
