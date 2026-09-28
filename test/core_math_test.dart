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
    final nte = GameId.nte.config;
    final t0 = DateTime(2026, 7, 1, 12, 0);
    EnergySnapshot at(GameConfig g, int energy, Duration elapsed,
            {int reserve = 0, int? cap}) =>
        projectEnergy(g,
            energy: energy,
            reserve: reserve,
            cap: cap,
            anchorTime: t0,
            now: t0.add(elapsed));

    test('normal regen: 1 per 6 minutes', () {
      expect(at(hsr, 100, const Duration(hours: 1)).current, 110);
    });

    test('caps at normal cap then fills the reserve at its own rate', () {
      // 10 below cap -> 60 min to cap, then 3h at 1/18min = 10 reserve.
      final snap = at(hsr, 290, const Duration(hours: 4));
      expect(snap.current, 300);
      expect(snap.reserve, 10);
    });

    test('HSR reserve holds 2400 on top of the 300 main pool', () {
      final snap = at(hsr, 300, const Duration(days: 40));
      expect(snap.current, 300);
      expect(snap.reserve, 2400);
      expect(snap.wasting, isTrue);
      // 2400 * 18 min = 30 days from a full main pool.
      expect(at(hsr, 300, const Duration(days: 29)).reserveFull, isFalse);
    });

    test('WuWa crystals: 1 per 12 minutes, 480 on top of 240 Waveplates', () {
      final snap = at(wuwa, 240, const Duration(hours: 2));
      expect(snap.current, 240);
      expect(snap.reserve, 10);
      final three = at(wuwa, 240, const Duration(days: 3));
      expect(three.reserve, 360, reason: 'not capped yet at 3 days');
      final full = at(wuwa, 240, const Duration(days: 4));
      expect(full.reserve, 480);
      expect(full.wasting, isTrue);
    });

    test('reserve does not grow while the main pool is below cap', () {
      final snap = at(hsr, 100, const Duration(hours: 1), reserve: 500);
      expect(snap.current, 110);
      expect(snap.reserve, 500);
    });

    test('overfilled main pool pauses regen; the reserve keeps filling', () {
      final wu = at(wuwa, 300, const Duration(hours: 1));
      expect(wu.current, 300);
      expect(wu.overfilled, isTrue);
      expect(wu.reserve, 5);
      final gi = at(GameId.genshin.config, 260, const Duration(hours: 5));
      expect(gi.current, 260);
      expect(gi.wasting, isTrue);
    });

    test('no-reserve game stops at cap', () {
      final snap = at(re, 239, const Duration(days: 1));
      expect(snap.current, 240);
      expect(snap.capAt, isNull);
      expect(snap.reserveFullAt, isNull);
      expect(snap.wasting, isTrue);
    });

    test('cap ETA matches regen math', () {
      expect(at(hsr, 240, Duration.zero).capAt,
          t0.add(const Duration(minutes: 360)));
    });

    test('reserve ETA counts the time to fill the main pool first', () {
      final snap = at(wuwa, 230, Duration.zero, reserve: 470);
      // 10 * 6 min to cap, then 10 * 12 min of crystals.
      expect(snap.reserveFullAt, t0.add(const Duration(minutes: 60 + 120)));
    });

    test('NTE Character Pixels: 240 base cap at 1 per 6 minutes', () {
      expect(nte.energyName, 'Character Pixels');
      expect(nte.normalCap, 240);
      expect(nte.hasReserve, isFalse);
      expect(at(nte, 0, const Duration(hours: 24)).current, 240);
      expect(at(nte, 0, const Duration(hours: 30)).current, 240);
    });

    test("NTE Dream Weaver's Knot raises the cap up to 360", () {
      expect(nte.capOptions.first, 240);
      expect(nte.capOptions.last, 360);
      expect(nte.capOptions.length, 11, reason: 'not placed + Lv1..10');
      final snap = at(nte, 240, const Duration(hours: 10), cap: 360);
      expect(snap.current, 340);
      expect(snap.cap, 360);
      expect(snap.capAt, t0.add(const Duration(hours: 12)));
      expect(at(nte, 240, const Duration(hours: 13), cap: 360).current, 360);
    });
  });

  group('NTE City Stamina', () {
    test('cap steps at Tycoon levels 5, 10, 16 and 23', () {
      expect(nteCityStaminaForLevel(1), 100);
      expect(nteCityStaminaForLevel(4), 100);
      expect(nteCityStaminaForLevel(5), 200);
      expect(nteCityStaminaForLevel(10), 350);
      expect(nteCityStaminaForLevel(16), 500);
      expect(nteCityStaminaForLevel(22), 500);
      expect(nteCityStaminaForLevel(23), 700);
      expect(nteCityStaminaForLevel(45), 700);
      expect(nteCityStaminaForLevel(99), 700);
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

    test('NTE Limited Board: 0.99% until roll 70, then 19.59%, 90 guaranteed',
        () {
      expect(ratePerPull(nte, 1), 0.0099);
      expect(ratePerPull(nte, 70), 0.0099);
      expect(ratePerPull(nte, 71), 0.1959);
      expect(ratePerPull(nte, 89), 0.1959);
      expect(ratePerPull(nte, 90), 1.0);
      // Expected rolls per S-class ~53 => the published ~1.88% consolidated.
      final dist = firstTopRarityDistribution(nte, 0);
      var expected = 0.0;
      for (var k = 1; k < dist.length; k++) {
        expected += k * dist[k];
      }
      expect(1 / expected, closeTo(0.0188, 0.0005));
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
    // Server clocks: 04:00 at UTC+1 = 03:00 UTC; 05:00 at UTC+0 = 05:00 UTC.
    const eu = ServerReset(4, 1);
    const nte = ServerReset(5, 0);

    test('daily reset before/after the boundary', () {
      expect(lastDailyReset(eu, DateTime.utc(2026, 7, 10, 2, 59)).toUtc(),
          DateTime.utc(2026, 7, 9, 3));
      expect(lastDailyReset(eu, DateTime.utc(2026, 7, 10, 3, 0)).toUtc(),
          DateTime.utc(2026, 7, 10, 3));
      expect(nextDailyReset(eu, DateTime.utc(2026, 7, 10, 12)).toUtc(),
          DateTime.utc(2026, 7, 11, 3));
    });

    test('reset instant ignores daylight saving (same UTC hour all year)', () {
      final summer = lastDailyReset(eu, DateTime.utc(2026, 7, 10, 12));
      final winter = lastDailyReset(eu, DateTime.utc(2026, 12, 10, 12));
      expect(summer.toUtc().hour, 3);
      expect(winter.toUtc().hour, 3);
      expect(summer.isUtc, isFalse, reason: 'returned as device-local time');
    });

    test('NTE weekly reset anchors to Monday 05:00 server time', () {
      // 2026-07-10 is a Friday.
      final now = DateTime.utc(2026, 7, 10, 12);
      expect(lastWeeklyReset(DateTime.monday, nte, now).toUtc(),
          DateTime.utc(2026, 7, 6, 5));
      expect(nextWeeklyReset(DateTime.monday, nte, now).toUtc(),
          DateTime.utc(2026, 7, 13, 5));
      expect(lastWeeklyReset(DateTime.monday, nte, DateTime.utc(2026, 7, 13, 4))
          .toUtc(), DateTime.utc(2026, 7, 6, 5));
    });

    test('weekday is taken from the server calendar', () {
      // Monday 05:00 at UTC+8 is Sunday 21:00 UTC.
      const asia = ServerReset(5, 8);
      expect(
          lastWeeklyReset(DateTime.monday, asia, DateTime.utc(2026, 7, 12, 22))
              .toUtc(),
          DateTime.utc(2026, 7, 12, 21));
    });

    test('NTE daily and weekly resets share one server time', () {
      final now = DateTime.utc(2026, 7, 10, 12);
      final r = GameId.nte.config.reset;
      expect(lastWeeklyReset(DateTime.monday, r, now).toUtc().hour,
          lastDailyReset(r, now).toUtc().hour);
    });

    test('burn warning slot is the upcoming Sunday evening', () {
      final now = DateTime(2026, 7, 10, 12, 0);
      expect(nextWeekdayTime(DateTime.sunday, 19, now),
          DateTime(2026, 7, 12, 19));
    });

    test('burn warning keeps its local hour across a DST switch', () {
      // Europe leaves summer time on Sunday 2026-10-25.
      final now = DateTime(2026, 10, 19, 12, 0);
      expect(nextWeekdayTime(DateTime.sunday, 19, now),
          DateTime(2026, 10, 25, 19));
    });
  });
}
