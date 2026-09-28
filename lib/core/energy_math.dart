import 'dart:math';

import 'games.dart';

/// Point-in-time projection of one account's energy: the main pool plus, for
/// games that have one, the separate reserve pool.
class EnergySnapshot {
  const EnergySnapshot({
    required this.game,
    required this.cap,
    required this.exact,
    required this.exactReserve,
    required this.capAt,
    required this.reserveFullAt,
  });

  final GameConfig game;

  /// The account's regen cap: the game's, or an unlocked upgrade of it.
  final int cap;

  /// Fractional main-pool energy right now. Can exceed [cap] after refills,
  /// in which case it does not regenerate.
  final double exact;

  /// Fractional reserve right now (always 0 for games without one).
  final double exactReserve;

  /// When the main pool reaches [cap]. null = already at/above it.
  final DateTime? capAt;

  /// When the reserve fills up. null = no reserve, or it is already full.
  final DateTime? reserveFullAt;

  int get current => exact.floor();
  int get reserve => exactReserve.floor();
  bool get atCap => exact >= cap;
  bool get overfilled => exact > cap;
  bool get reserveFull =>
      game.hasReserve && exactReserve >= game.reserveCap!;

  /// Nothing regenerates any more, so regen time is being wasted.
  bool get wasting => atCap && (!game.hasReserve || reserveFull);

  double get fraction => (exact / cap).clamp(0.0, 1.0);
  double get reserveFraction => game.hasReserve
      ? (exactReserve / game.reserveCap!).clamp(0.0, 1.0)
      : 0.0;
}

/// Projects an account's energy forward from its anchor ([energy] in the main
/// pool and [reserve] in the reserve pool at [anchorTime]) to [now].
///
/// Regeneration is piecewise:
///   phase 1: main pool +1 per [GameConfig.normalRateMinutes] until [cap]
///            (the game's normal cap unless the account unlocked a higher one),
///   phase 2: while the main pool is at/above its cap, the reserve (if any)
///            +1 per [GameConfig.reserveRateMinutes] until its own cap.
/// A main pool refilled above its cap stays put; only the reserve grows.
EnergySnapshot projectEnergy(
  GameConfig g, {
  required int energy,
  int reserve = 0,
  int? cap,
  required DateTime anchorTime,
  required DateTime now,
}) {
  final c = cap ?? g.normalCap;
  final rCap = g.reserveCap;
  double e = max(0, energy).toDouble();
  double r = rCap == null ? 0 : reserve.clamp(0, rCap).toDouble();
  double minutesLeft =
      max(0, now.difference(anchorTime).inMilliseconds) / 60000.0;

  if (e < c) {
    final minutesToCap = (c - e) * g.normalRateMinutes;
    if (minutesLeft >= minutesToCap) {
      minutesLeft -= minutesToCap;
      e = c.toDouble();
    } else {
      e += minutesLeft / g.normalRateMinutes;
      minutesLeft = 0;
    }
  }

  if (rCap != null && minutesLeft > 0 && r < rCap) {
    r = min(rCap.toDouble(), r + minutesLeft / g.reserveRateMinutes!);
  }

  final minutesToCap = e >= c ? 0.0 : (c - e) * g.normalRateMinutes;
  return EnergySnapshot(
    game: g,
    cap: c,
    exact: e,
    exactReserve: r,
    capAt: e >= c ? null : now.add(_minutes(minutesToCap)),
    reserveFullAt: rCap == null || r >= rCap
        ? null
        : now.add(
            _minutes(minutesToCap + (rCap - r) * g.reserveRateMinutes!)),
  );
}

Duration _minutes(double m) => Duration(milliseconds: (m * 60000).ceil());
