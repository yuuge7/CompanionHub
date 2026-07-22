import 'dart:math';

import 'games.dart';

/// Point-in-time projection of a game's energy given a stored anchor value.
class EnergySnapshot {
  const EnergySnapshot({
    required this.exact,
    required this.game,
    required this.normalCapAt,
    required this.absoluteCapAt,
  });

  final GameConfig game;

  /// Fractional energy right now (normal + overflow combined).
  final double exact;

  /// When the normal cap will be reached. null = already at/above it.
  final DateTime? normalCapAt;

  /// When the absolute cap (overflow cap, or normal cap for games without
  /// overflow) will be reached. null = already there.
  final DateTime? absoluteCapAt;

  int get current => min(exact.floor(), game.absoluteCap);
  int get normalPortion => min(current, game.normalCap);
  int get overflowPortion => max(0, current - game.normalCap);
  bool get atNormalCap => exact >= game.normalCap;
  bool get atAbsoluteCap => exact >= game.absoluteCap;
  double get normalFraction => (exact / game.normalCap).clamp(0.0, 1.0);
  double get overflowFraction => game.hasOverflow
      ? ((exact - game.normalCap) / (game.absoluteCap - game.normalCap))
          .clamp(0.0, 1.0)
      : 0.0;
}

/// Projects energy forward from ([anchorValue] at [anchorTime]) to [now].
///
/// Regeneration is piecewise:
///   phase 1: 1 energy per [normalRateMinutes] until normalCap,
///   phase 2: 1 energy per [overflowRateMinutes] until overflowCap (if any).
EnergySnapshot projectEnergy(
  GameConfig g,
  int anchorValue,
  DateTime anchorTime,
  DateTime now,
) {
  double e = anchorValue.clamp(0, g.absoluteCap).toDouble();
  double minutesLeft =
      max(0, now.difference(anchorTime).inMilliseconds) / 60000.0;

  if (e < g.normalCap) {
    final minutesToCap = (g.normalCap - e) * g.normalRateMinutes;
    if (minutesLeft >= minutesToCap) {
      minutesLeft -= minutesToCap;
      e = g.normalCap.toDouble();
    } else {
      e += minutesLeft / g.normalRateMinutes;
      minutesLeft = 0;
    }
  }

  final oCap = g.overflowCap;
  if (oCap != null && minutesLeft > 0 && e < oCap) {
    e = min(oCap.toDouble(), e + minutesLeft / g.overflowRateMinutes!);
  }

  return EnergySnapshot(
    exact: e,
    game: g,
    normalCapAt: e >= g.normalCap
        ? null
        : now.add(_minutes((g.normalCap - e) * g.normalRateMinutes)),
    absoluteCapAt: e >= g.absoluteCap ? null : now.add(_minutes(_minutesToAbsoluteCap(g, e))),
  );
}

double _minutesToAbsoluteCap(GameConfig g, double e) {
  double mins = 0;
  double t = e;
  if (t < g.normalCap) {
    mins += (g.normalCap - t) * g.normalRateMinutes;
    t = g.normalCap.toDouble();
  }
  final oCap = g.overflowCap;
  if (oCap != null && t < oCap) {
    mins += (oCap - t) * g.overflowRateMinutes!;
  }
  return mins;
}

Duration _minutes(double m) => Duration(milliseconds: (m * 60000).ceil());
