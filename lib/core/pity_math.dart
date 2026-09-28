import 'dart:math';

import 'games.dart';

/// Per-pull probability of hitting the top rarity on pull [pullNumber]
/// (1-indexed pulls since the last top-rarity drop).
double ratePerPull(GameConfig g, int pullNumber) {
  if (pullNumber >= g.hardPity) return 1.0;
  if (pullNumber < g.softPityStart) return g.baseRate;
  final flat = g.softPityFlatRate;
  if (flat != null) return flat;
  return min(
    1.0,
    g.baseRate + (pullNumber - g.softPityStart + 1) * g.softPityIncrement,
  );
}

/// dist[k] = P(first top-rarity lands exactly on the k-th pull from now),
/// for k in 1..(hardPity - currentPity). Index 0 is unused.
List<double> firstTopRarityDistribution(GameConfig g, int currentPity) {
  final maxK = max(0, g.hardPity - currentPity);
  final dist = List<double>.filled(maxK + 1, 0.0);
  var survive = 1.0;
  for (var k = 1; k <= maxK; k++) {
    final p = ratePerPull(g, currentPity + k);
    dist[k] = survive * p;
    survive *= (1 - p);
  }
  return dist;
}

/// P(securing the FEATURED character within [pulls] pulls), starting from
/// [currentPity] with [guaranteed] rate-up status.
///
/// * NTE (has5050 == false): every S-Rank is the featured character, so this
///   is simply P(at least one top-rarity within pulls).
/// * HSR / WuWa / Re:1999: 50/50 on the first top-rarity; losing it makes the
///   next top-rarity guaranteed featured. Computed exactly by convolving the
///   first-drop distribution with a fresh-pity second-drop distribution.
double chanceOfFeatured(
  GameConfig g,
  int currentPity,
  bool guaranteed,
  int pulls,
) {
  if (pulls <= 0) return 0.0;

  final d1 = firstTopRarityDistribution(g, currentPity);

  if (!g.has5050 || guaranteed) {
    var sum = 0.0;
    for (var k = 1; k < d1.length && k <= pulls; k++) {
      sum += d1[k];
    }
    return sum.clamp(0.0, 1.0);
  }

  // Cumulative distribution of a fresh-pity top-rarity (the guaranteed one
  // after losing the flip): c2[n] = P(second drop needs <= n pulls).
  final d2 = firstTopRarityDistribution(g, 0);
  final c2 = List<double>.filled(d2.length, 0.0);
  for (var n = 1; n < d2.length; n++) {
    c2[n] = c2[n - 1] + d2[n];
  }
  double cumulative2(int n) {
    if (n <= 0) return 0.0;
    return n >= c2.length ? 1.0 : c2[n];
  }

  var total = 0.0;
  for (var k = 1; k < d1.length && k <= pulls; k++) {
    // Win the flip outright, or lose it and land the guaranteed drop in time.
    total += d1[k] * (0.5 + 0.5 * cumulative2(pulls - k));
  }
  return total.clamp(0.0, 1.0);
}

/// Guaranteed-worst-case pulls to secure the featured character.
int worstCasePulls(GameConfig g, int currentPity, bool guaranteed) {
  final first = g.hardPity - currentPity;
  if (!g.has5050 || guaranteed) return max(0, first);
  return max(0, first) + g.hardPity;
}
