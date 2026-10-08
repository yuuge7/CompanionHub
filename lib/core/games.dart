import 'package:flutter/material.dart';

import 'reset_time.dart';

/// The supported games. New games are appended so each game's [Enum.index]
/// (used in notification ids) stays stable across releases.
enum GameId { hsr, wuwa, re1999, nte, genshin, zzz }

extension GameIdX on GameId {
  GameConfig get config => kGames[this]!;

  /// Stable string key used for Hive keys and home_widget SharedPreferences.
  String get key => name;
}

/// Upper bound for a typed-in energy value. Refill items push the main pool
/// well past its regen cap in every game, so the cap is not the limit.
const int kEnergyInputLimit = 9999;

/// Static, game-specific tuning. All rates are "minutes per 1 energy".
@immutable
class GameConfig {
  const GameConfig({
    required this.id,
    required this.name,
    required this.shortName,
    required this.color,
    required this.energyName,
    required this.currencyName,
    required this.pullName,
    required this.normalCap,
    required this.normalRateMinutes,
    this.capOptions = const [],
    this.capUpgradeName,
    this.reserveName,
    this.reserveCap,
    this.reserveRateMinutes,
    this.quickDeltas = const [-60, -30, -10],
    required this.pullCost,
    required this.hardPity,
    required this.softPityStart,
    required this.baseRate,
    this.softPityIncrement = 0,
    this.softPityFlatRate,
    required this.has5050,
    required this.reset,
    required this.dailyTasks,
  })  : assert((reserveCap == null) == (reserveRateMinutes == null) &&
            (reserveCap == null) == (reserveName == null)),
        assert((softPityFlatRate == null) != (softPityIncrement == 0));

  final GameId id;
  final String name;
  final String shortName;
  final Color color;

  // -- Energy --
  final String energyName;

  /// Regen cap of the main pool: energy regenerates only below it. Refills can
  /// push the pool above it, which pauses regeneration.
  final int normalCap;
  final int normalRateMinutes;

  /// Caps an account can unlock, lowest (= [normalCap]) first, indexed by
  /// upgrade level. Empty = the cap is fixed.
  final List<int> capOptions;

  /// What raises the cap in-game, e.g. NTE's "Dream Weaver's Knot".
  final String? capUpgradeName;

  /// Separate overflow pool that fills only while the main pool is at/above
  /// its cap (HSR Reserved Trailblaze Power, WuWa Waveplate Crystals, ZZZ
  /// Backup Battery Charge). It is
  /// not spent by activities, so it is tracked apart from the main pool.
  /// null = the game has no reserve and regeneration simply stops at the cap.
  final String? reserveName;
  final int? reserveCap;
  final int? reserveRateMinutes;

  /// Negative quick-spend amounts offered as chips in the energy editor,
  /// matching the game's common activity costs. Largest spend first.
  final List<int> quickDeltas;

  // -- Gacha --
  final String currencyName;
  final String pullName;
  final int pullCost;
  final int hardPity;

  /// Pull number (since last top-rarity) at which soft pity begins.
  final int softPityStart;

  /// Base per-pull top-rarity probability before soft pity.
  final double baseRate;

  /// Linear probability increase per pull once inside soft pity.
  final double softPityIncrement;

  /// Flat per-pull probability once inside soft pity, for games whose rate
  /// jumps instead of ramping (NTE's Modified Board). Replaces the ramp.
  final double? softPityFlatRate;

  /// true = losing the rate-up flip guarantees the next top-rarity is featured.
  /// false = every top-rarity IS the featured character (NTE).
  final bool has5050;

  // -- Resets & tasks --
  /// Daily (and, where the game has one, weekly) server reset.
  final ServerReset reset;
  final List<String> dailyTasks;

  bool get hasReserve => reserveCap != null;
  bool get hasCapUpgrades => capOptions.isNotEmpty;
}

final Map<GameId, GameConfig> kGames = {
  GameId.hsr: const GameConfig(
    id: GameId.hsr,
    name: 'Honkai: Star Rail',
    shortName: 'HSR',
    color: Color(0xFFB0A8FF),
    energyName: 'Trailblaze Power',
    currencyName: 'Stellar Jade',
    pullName: 'Warps',
    normalCap: 300,
    normalRateMinutes: 6,
    reserveName: 'Reserved Trailblaze Power',
    reserveCap: 2400,
    reserveRateMinutes: 18,
    quickDeltas: [-240, -200, -60, -40, -30, -10],
    pullCost: 160,
    hardPity: 90,
    softPityStart: 74,
    baseRate: 0.006,
    softPityIncrement: 0.06,
    has5050: true,
    reset: ServerReset(4, 1), // Europe server
    dailyTasks: [
      'Daily Training: 500 activity',
      'Claim Assignment rewards',
      'Spend Trailblaze Power',
      'Claim Daily Training chest',
    ],
  ),
  GameId.wuwa: const GameConfig(
    id: GameId.wuwa,
    name: 'Wuthering Waves',
    shortName: 'WuWa',
    color: Color(0xFF5CE0D5),
    energyName: 'Waveplates',
    currencyName: 'Astrite',
    pullName: 'Convenes',
    normalCap: 240,
    normalRateMinutes: 6,
    reserveName: 'Waveplate Crystals',
    reserveCap: 480,
    reserveRateMinutes: 12,
    quickDeltas: [-80, -60, -40],
    pullCost: 160,
    hardPity: 80,
    softPityStart: 66,
    baseRate: 0.008,
    softPityIncrement: 0.08,
    has5050: true,
    reset: ServerReset(4, 1), // Europe server
    dailyTasks: [
      'Activity Points: 100',
      'Spend Waveplates',
      'Claim Guidebook rewards',
      'Tacet Field / Echo run',
    ],
  ),
  GameId.re1999: const GameConfig(
    id: GameId.re1999,
    name: 'Reverse: 1999',
    shortName: 'Re:1999',
    color: Color(0xFFE3C084),
    energyName: 'Activity',
    currencyName: 'Clear Drops',
    pullName: 'Summons',
    normalCap: 240,
    normalRateMinutes: 6,
    pullCost: 180,
    hardPity: 70,
    softPityStart: 61,
    baseRate: 0.015,
    softPityIncrement: 0.025,
    has5050: true,
    reset: ServerReset(5, -5), // Global server
    dailyTasks: [
      'Spend Activity',
      'Collect Wilderness income',
      'Complete daily missions',
      'Claim free shop/mail items',
    ],
  ),
  GameId.nte: const GameConfig(
    id: GameId.nte,
    name: 'Neverness to Everness',
    shortName: 'NTE',
    color: Color(0xFFFF7FA3),
    energyName: 'Character Pixels',
    currencyName: 'Annulith',
    pullName: 'Solid Dice',
    normalCap: 240,
    normalRateMinutes: 6,
    // Dream Weaver's Knot (Anomaly Furniture) raises the Pixel cap per level:
    // none = 240, Lv1..10 = 255 ... 360. Regen stays 1 per 6 minutes.
    capOptions: [240, 255, 270, 285, 300, 310, 320, 330, 340, 350, 360],
    capUpgradeName: "Dream Weaver's Knot",
    // Anomaly Zone 40 (double rewards 80), Anomaly Pilgrimage 60.
    quickDeltas: [-80, -60, -40],
    pullCost: 160,
    hardPity: 90,
    // Limited Board: 0.99% per roll; after 70 rolls without an S-class the
    // board becomes a Modified Board at 19.59% per roll; roll 90 guarantees
    // the featured S-class. Together that is the 1.88% consolidated rate.
    softPityStart: 71,
    baseRate: 0.0099,
    softPityFlatRate: 0.1959,
    has5050: false, // S-Rank is always the featured character
    // "05:00 server time" on the Europe server lands at 05:00 UTC
    // (06:00 CET / 07:00 EET), i.e. that server runs on UTC+0.
    reset: ServerReset(5, 0),
    dailyTasks: [
      'Spend Character Pixels',
      'Nacupeda Pool Wish',
      "Witch's House Fortune",
      'Cafe Restock',
      'Claim Daily Quests (1,000 EXP)',
    ],
  ),
  GameId.genshin: const GameConfig(
    id: GameId.genshin,
    name: 'Genshin Impact',
    shortName: 'GI',
    color: Color(0xFF8FD16A),
    energyName: 'Original Resin',
    currencyName: 'Primogems',
    pullName: 'Fates',
    normalCap: 200,
    normalRateMinutes: 8,
    // Domain / ley line 20, weekly boss 30 (60 after the 3 discounted runs),
    // normal boss or Condensed Resin 40.
    quickDeltas: [-60, -40, -30, -20],
    pullCost: 160,
    hardPity: 90,
    softPityStart: 74,
    baseRate: 0.006,
    softPityIncrement: 0.06,
    // Capturing Radiance nudges the real flip slightly above 50%; modelled as
    // a plain 50/50 so the forecast stays conservative.
    has5050: true,
    reset: ServerReset(4, 1), // Europe server
    dailyTasks: [
      'Daily Commissions (4)',
      'Claim Commission bonus (Katheryne)',
      'Spend Original Resin',
      'Collect & resend Expeditions',
      'Serenitea Pot: realm currency',
    ],
  ),
  GameId.zzz: const GameConfig(
    id: GameId.zzz,
    name: 'Zenless Zone Zero',
    shortName: 'ZZZ',
    color: Color(0xFFFF9F43),
    energyName: 'Battery Charge',
    currencyName: 'Polychrome',
    pullName: 'Master Tapes',
    normalCap: 240,
    normalRateMinutes: 6,
    reserveName: 'Backup Battery Charge',
    reserveCap: 2400,
    reserveRateMinutes: 18,
    // Combat Simulation 20 per card (1-5 cards), Expert Challenge 40,
    // Routine Cleanup / Notorious Hunt 60.
    quickDeltas: [-100, -60, -40, -20],
    pullCost: 160,
    hardPity: 90,
    softPityStart: 74,
    baseRate: 0.006,
    softPityIncrement: 0.06,
    has5050: true,
    reset: ServerReset(4, 1), // Europe server
    dailyTasks: [
      'Errands: 400 Engagement',
      'Spend Battery Charge',
      'Coff Cafe: daily coffee',
      "Howl's newsstand: scratch card",
      'Open the Video Store',
    ],
  ),
};

// ===== NTE weekly system =====

/// NTE weekly limits reset Monday at the daily reset time (05:00 server).
const int kNteWeeklyResetWeekday = DateTime.monday;

/// Burn-warning fires Sunday evening at this local hour if weeklies are
/// unfinished.
const int kNteBurnWarningHour = 19;

/// Anomaly Pilgrimage is capped at three claims (60 Character Pixels each)
/// per week; Realm of Greed is the weekly Fons boss.
const List<String> kNteWeeklyTasks = [
  'Anomaly Pilgrimage 1/3',
  'Anomaly Pilgrimage 2/3',
  'Anomaly Pilgrimage 3/3',
  'Realm of Greed',
];

const int kNteMaxTycoonLevel = 45;

/// Max City Stamina by City Tycoon level. The cap only changes at levels 5,
/// 10, 16 and 23 (then stays 700 up to the level-45 max). City Stamina does
/// not regenerate: it refills to this cap at the weekly reset.
int nteCityStaminaForLevel(int tycoonLevel) {
  final lvl = tycoonLevel.clamp(1, kNteMaxTycoonLevel);
  if (lvl >= 23) return 700;
  if (lvl >= 16) return 500;
  if (lvl >= 10) return 350;
  if (lvl >= 5) return 200;
  return 100;
}
