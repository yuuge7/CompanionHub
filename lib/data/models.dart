import 'package:flutter/foundation.dart';

import '../core/games.dart';

/// Anchor for energy projection: "the user had [energy] at [updatedAt]".
@immutable
class EnergyState {
  const EnergyState({
    required this.game,
    required this.energy,
    required this.updatedAtMs,
    this.notifyCap = true,
  });

  final GameId game;
  final int energy;
  final int updatedAtMs;
  final bool notifyCap;

  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  EnergyState copyWith({int? energy, int? updatedAtMs, bool? notifyCap}) =>
      EnergyState(
        game: game,
        energy: energy ?? this.energy,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        notifyCap: notifyCap ?? this.notifyCap,
      );

  Map<String, dynamic> toJson() => {
        'game': game.key,
        'energy': energy,
        'updatedAtMs': updatedAtMs,
        'notifyCap': notifyCap,
      };

  static EnergyState fromJson(GameId game, Map<dynamic, dynamic> j) =>
      EnergyState(
        game: game,
        energy: (j['energy'] as num?)?.toInt() ?? 0,
        updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        notifyCap: j['notifyCap'] as bool? ?? true,
      );

  static EnergyState initial(GameId game) => EnergyState(
        game: game,
        energy: 0,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
}

/// Pity Forecaster inputs for one game.
@immutable
class PityPlan {
  const PityPlan({
    required this.game,
    this.pity = 0,
    this.guaranteed = false,
    this.currency = 0,
    this.ownedPulls = 0,
    this.dailyIncome = 60,
    this.weeklyIncome = 0,
    this.targetDateMs,
  });

  final GameId game;
  final int pity;
  final bool guaranteed;

  /// Raw premium currency (Stellar Jade / Astrite / Clear Drops / ...).
  final int currency;

  /// Pull tickets already owned (Special Passes, Radiant Tides, Unilogs...).
  final int ownedPulls;
  final int dailyIncome;
  final int weeklyIncome;
  final int? targetDateMs;

  DateTime? get targetDate => targetDateMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(targetDateMs!);

  PityPlan copyWith({
    int? pity,
    bool? guaranteed,
    int? currency,
    int? ownedPulls,
    int? dailyIncome,
    int? weeklyIncome,
    int? targetDateMs,
    bool clearTargetDate = false,
  }) =>
      PityPlan(
        game: game,
        pity: pity ?? this.pity,
        guaranteed: guaranteed ?? this.guaranteed,
        currency: currency ?? this.currency,
        ownedPulls: ownedPulls ?? this.ownedPulls,
        dailyIncome: dailyIncome ?? this.dailyIncome,
        weeklyIncome: weeklyIncome ?? this.weeklyIncome,
        targetDateMs: clearTargetDate ? null : (targetDateMs ?? this.targetDateMs),
      );

  /// Currency projected at [target] (inclusive day count from [now]).
  int projectedCurrency(DateTime now, DateTime target) {
    if (!target.isAfter(now)) return currency;
    final days = target.difference(now).inDays;
    final weeks = days ~/ 7;
    return currency + days * dailyIncome + weeks * weeklyIncome;
  }

  Map<String, dynamic> toJson() => {
        'game': game.key,
        'pity': pity,
        'guaranteed': guaranteed,
        'currency': currency,
        'ownedPulls': ownedPulls,
        'dailyIncome': dailyIncome,
        'weeklyIncome': weeklyIncome,
        'targetDateMs': targetDateMs,
      };

  static PityPlan fromJson(GameId game, Map<dynamic, dynamic> j) => PityPlan(
        game: game,
        pity: (j['pity'] as num?)?.toInt() ?? 0,
        guaranteed: j['guaranteed'] as bool? ?? false,
        currency: (j['currency'] as num?)?.toInt() ?? 0,
        ownedPulls: (j['ownedPulls'] as num?)?.toInt() ?? 0,
        dailyIncome: (j['dailyIncome'] as num?)?.toInt() ?? 60,
        weeklyIncome: (j['weeklyIncome'] as num?)?.toInt() ?? 0,
        targetDateMs: (j['targetDateMs'] as num?)?.toInt(),
      );
}

/// NTE weekly dashboard state. [weekStartMs] anchors the Monday-05:00 window
/// the checklist belongs to; when a new week starts the flags are reset.
@immutable
class NteWeeklyState {
  const NteWeeklyState({
    required this.tycoonLevel,
    required this.done,
    required this.weekStartMs,
  });

  final int tycoonLevel;

  /// One flag per entry in kNteWeeklyTasks (3 bosses + Realm of Greed).
  final List<bool> done;
  final int weekStartMs;

  bool get allDone => done.every((d) => d);
  int get remaining => done.where((d) => !d).length;

  NteWeeklyState copyWith({int? tycoonLevel, List<bool>? done, int? weekStartMs}) =>
      NteWeeklyState(
        tycoonLevel: tycoonLevel ?? this.tycoonLevel,
        done: done ?? this.done,
        weekStartMs: weekStartMs ?? this.weekStartMs,
      );

  Map<String, dynamic> toJson() => {
        'tycoonLevel': tycoonLevel,
        'done': done,
        'weekStartMs': weekStartMs,
      };

  static NteWeeklyState fromJson(Map<dynamic, dynamic> j) => NteWeeklyState(
        tycoonLevel: (j['tycoonLevel'] as num?)?.toInt() ?? 1,
        done: (j['done'] as List?)?.map((e) => e == true).toList() ??
            List.filled(4, false),
        weekStartMs: (j['weekStartMs'] as num?)?.toInt() ?? 0,
      );

  static NteWeeklyState initial() =>
      NteWeeklyState(tycoonLevel: 1, done: List.filled(4, false), weekStartMs: 0);
}

/// Global app settings.
@immutable
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.sleepSafeEnabled = true,
    this.sleepStartMinutes = 23 * 60, // 23:00
    this.sleepEndMinutes = 7 * 60, // 07:00
    this.summaryHour = 8, // silent morning summary
    this.burnWarningEnabled = true,
    this.hiddenGames = const {},
  });

  final bool notificationsEnabled;
  final bool sleepSafeEnabled;

  /// Games hidden from every tab, the overlay bubble and the home widget.
  /// Hidden games keep their saved data and fire no alerts.
  final Set<GameId> hiddenGames;

  /// Sleep window bounds as minutes-since-midnight; window may cross midnight.
  final int sleepStartMinutes;
  final int sleepEndMinutes;
  final int summaryHour;
  final bool burnWarningEnabled;

  bool isHidden(GameId g) => hiddenGames.contains(g);

  /// Games shown in tabs/overlay/widget, in canonical order. The settings UI
  /// refuses to hide the last visible game, so this is never empty in practice.
  List<GameId> get visibleGames =>
      [for (final g in GameId.values) if (!hiddenGames.contains(g)) g];

  /// Whether [t] falls inside the sleep window.
  bool isAsleep(DateTime t) {
    final m = t.hour * 60 + t.minute;
    if (sleepStartMinutes <= sleepEndMinutes) {
      return m >= sleepStartMinutes && m < sleepEndMinutes;
    }
    return m >= sleepStartMinutes || m < sleepEndMinutes; // crosses midnight
  }

  /// First summary slot (summaryHour:00) at/after [t].
  DateTime nextSummaryTime(DateTime t) {
    var s = DateTime(t.year, t.month, t.day, summaryHour);
    if (!s.isAfter(t)) s = s.add(const Duration(days: 1));
    return s;
  }

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? sleepSafeEnabled,
    int? sleepStartMinutes,
    int? sleepEndMinutes,
    int? summaryHour,
    bool? burnWarningEnabled,
    Set<GameId>? hiddenGames,
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        sleepSafeEnabled: sleepSafeEnabled ?? this.sleepSafeEnabled,
        sleepStartMinutes: sleepStartMinutes ?? this.sleepStartMinutes,
        sleepEndMinutes: sleepEndMinutes ?? this.sleepEndMinutes,
        summaryHour: summaryHour ?? this.summaryHour,
        burnWarningEnabled: burnWarningEnabled ?? this.burnWarningEnabled,
        hiddenGames: hiddenGames ?? this.hiddenGames,
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'sleepSafeEnabled': sleepSafeEnabled,
        'sleepStartMinutes': sleepStartMinutes,
        'sleepEndMinutes': sleepEndMinutes,
        'summaryHour': summaryHour,
        'burnWarningEnabled': burnWarningEnabled,
        'hiddenGames': [for (final g in hiddenGames) g.key],
      };

  static AppSettings fromJson(Map<dynamic, dynamic> j) {
    final byName = GameId.values.asNameMap();
    return AppSettings(
      notificationsEnabled: j['notificationsEnabled'] as bool? ?? true,
      sleepSafeEnabled: j['sleepSafeEnabled'] as bool? ?? true,
      sleepStartMinutes: (j['sleepStartMinutes'] as num?)?.toInt() ?? 23 * 60,
      sleepEndMinutes: (j['sleepEndMinutes'] as num?)?.toInt() ?? 7 * 60,
      summaryHour: (j['summaryHour'] as num?)?.toInt() ?? 8,
      burnWarningEnabled: j['burnWarningEnabled'] as bool? ?? true,
      hiddenGames: {
        for (final k in (j['hiddenGames'] as List? ?? const []))
          if (byName[k] != null) byName[k]!,
      },
    );
  }
}
