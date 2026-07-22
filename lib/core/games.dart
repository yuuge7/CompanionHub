import 'package:flutter/material.dart';

/// The four supported games.
enum GameId { hsr, wuwa, re1999, nte }

extension GameIdX on GameId {
  GameConfig get config => kGames[this]!;

  /// Stable string key used for Hive keys and home_widget SharedPreferences.
  String get key => name;
}

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
    this.overflowCap,
    this.overflowRateMinutes,
    required this.pullCost,
    required this.hardPity,
    required this.softPityStart,
    required this.baseRate,
    required this.softPityIncrement,
    required this.has5050,
    required this.dailyResetHour,
    required this.dailyTasks,
  }) : assert((overflowCap == null) == (overflowRateMinutes == null));

  final GameId id;
  final String name;
  final String shortName;
  final Color color;

  // -- Energy --
  final String energyName;
  final int normalCap;
  final int normalRateMinutes;

  /// Absolute cap including overflow. null = game has no overflow reserve.
  final int? overflowCap;
  final int? overflowRateMinutes;

  // -- Gacha --
  final String currencyName;
  final String pullName;
  final int pullCost;
  final int hardPity;

  /// Pull number (since last top-rarity) at which soft pity ramp begins.
  final int softPityStart;

  /// Base per-pull top-rarity probability before soft pity.
  final double baseRate;

  /// Linear probability increase per pull once inside soft pity.
  final double softPityIncrement;

  /// true = losing the rate-up flip guarantees the next top-rarity is featured.
  /// false = every top-rarity IS the featured character (NTE).
  final bool has5050;

  // -- Resets & tasks --
  /// Server daily reset hour, expressed in the device's local time zone.
  final int dailyResetHour;
  final List<String> dailyTasks;

  bool get hasOverflow => overflowCap != null;
  int get absoluteCap => overflowCap ?? normalCap;
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
    overflowCap: 2400,
    overflowRateMinutes: 18,
    pullCost: 160,
    hardPity: 90,
    softPityStart: 74,
    baseRate: 0.006,
    softPityIncrement: 0.06,
    has5050: true,
    dailyResetHour: 6,
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
    overflowCap: 480,
    overflowRateMinutes: 12,
    pullCost: 160,
    hardPity: 80,
    softPityStart: 66,
    baseRate: 0.008,
    softPityIncrement: 0.08,
    has5050: true,
    dailyResetHour: 6,
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
    overflowCap: null,
    overflowRateMinutes: null,
    pullCost: 180,
    hardPity: 70,
    softPityStart: 61,
    baseRate: 0.015,
    softPityIncrement: 0.025,
    has5050: true,
    dailyResetHour: 13,
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
    energyName: 'Energy',
    currencyName: 'Premium Currency',
    pullName: 'Wishes',
    normalCap: 240,
    normalRateMinutes: 6,
    overflowCap: null,
    overflowRateMinutes: null,
    pullCost: 160,
    hardPity: 90,
    // NTE soft-pity curve is not officially published; values are a
    // community approximation — adjust here when confirmed.
    softPityStart: 74,
    baseRate: 0.01,
    softPityIncrement: 0.06,
    has5050: false, // S-Rank is always the featured character
    dailyResetHour: 8,
    dailyTasks: [
      'Spend Pixels',
      'Nacupeda Pool Wish',
      "Witch's House Fortune",
      'Cafe Restock',
      'Spend Energy',
    ],
  ),
};

// ===== NTE weekly system =====

/// NTE weekly limits reset Monday 05:00 (device-local approximation of server).
const int kNteWeeklyResetWeekday = DateTime.monday;
const int kNteWeeklyResetHour = 5;

/// Burn-warning fires Sunday evening at this hour if weeklies are unfinished.
const int kNteBurnWarningHour = 19;

const List<String> kNteWeeklyTasks = [
  'Weekly Boss 1',
  'Weekly Boss 2',
  'Weekly Boss 3',
  'Realm of Greed',
];

/// Max City Stamina by City Tycoon level.
/// NOTE: placeholder progression — official per-level values are not yet
/// published; tune the base/step here once confirmed in-game.
int nteCityStaminaForLevel(int tycoonLevel) {
  final lvl = tycoonLevel.clamp(1, 60);
  return 120 + lvl * 12;
}
