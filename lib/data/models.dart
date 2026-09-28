import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/energy_math.dart';
import '../core/games.dart';

/// Most accounts (main included) that can be tracked for a single game.
const int kMaxAccountsPerGame = 10;

/// Storage / state-map key of one account. The main account keeps the bare
/// game key, so data saved before multi-account mode existed is picked up
/// unchanged; extra accounts are keyed `<game>@<id>`.
String accountKey(GameId game, int accountId) =>
    accountId == Account.mainId ? game.key : '${game.key}@$accountId';

/// One player account of one game. Identity is ([game], [id]); [name] is
/// presentation only and does not take part in equality.
@immutable
class Account {
  const Account(this.game, this.id, [this.name = '']);

  /// The account every game starts with (and the only one used while
  /// multi-account mode is off).
  static const int mainId = 0;

  final GameId game;
  final int id;

  /// User-chosen label; empty = default ("Main" / "Account N").
  final String name;

  bool get isMain => id == mainId;
  String get key => accountKey(game, id);
  String get label =>
      name.isNotEmpty ? name : (isMain ? 'Main' : 'Account ${id + 1}');

  Account rename(String name) => Account(game, id, name.trim());

  @override
  bool operator ==(Object other) =>
      other is Account && other.game == game && other.id == id;

  @override
  int get hashCode => Object.hash(game, id);

  Map<String, dynamic> toJson() => {'game': game.key, 'id': id, 'name': name};

  static Account? fromJson(Map<dynamic, dynamic> j) {
    final game = GameId.values.asNameMap()[j['game']];
    final id = (j['id'] as num?)?.toInt();
    if (game == null || id == null || id < 0) return null;
    return Account(game, id, j['name'] as String? ?? '');
  }
}

/// Anchor for energy projection: "the account had [energy] (and [reserve])
/// at [updatedAt]".
@immutable
class EnergyState {
  const EnergyState({
    required this.game,
    this.accountId = Account.mainId,
    required this.energy,
    this.reserve = 0,
    this.cap,
    required this.updatedAtMs,
    this.notifyCap = true,
  });

  final GameId game;
  final int accountId;

  /// Main pool. May be above the cap after refills.
  final int energy;

  /// Reserve pool (HSR Reserved Trailblaze Power, WuWa Waveplate Crystals);
  /// always 0 for games without one.
  final int reserve;

  /// Regen cap the account unlocked (NTE Dream Weaver's Knot); null = the
  /// game's normal cap.
  final int? cap;
  final int updatedAtMs;
  final bool notifyCap;

  String get key => accountKey(game, accountId);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  int get effectiveCap => cap ?? game.config.normalCap;

  EnergySnapshot projectAt(DateTime now) => projectEnergy(
        game.config,
        energy: energy,
        reserve: reserve,
        cap: cap,
        anchorTime: updatedAt,
        now: now,
      );

  EnergyState copyWith({
    int? energy,
    int? reserve,
    int? cap,
    int? updatedAtMs,
    bool? notifyCap,
  }) =>
      EnergyState(
        game: game,
        accountId: accountId,
        energy: energy ?? this.energy,
        reserve: reserve ?? this.reserve,
        cap: cap ?? this.cap,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        notifyCap: notifyCap ?? this.notifyCap,
      );

  Map<String, dynamic> toJson() => {
        'game': game.key,
        'energy': energy,
        'reserve': reserve,
        'cap': cap,
        'updatedAtMs': updatedAtMs,
        'notifyCap': notifyCap,
      };

  static EnergyState fromJson(Account a, Map<dynamic, dynamic> j) {
    final cfg = a.game.config;
    var energy = (j['energy'] as num?)?.toInt() ?? 0;
    var reserve = (j['reserve'] as num?)?.toInt();
    if (reserve == null) {
      // Older versions folded the reserve into one number ("2000" = 300 TP +
      // 1700 reserve). Split it so existing anchors keep their meaning.
      reserve = 0;
      if (cfg.hasReserve && energy > cfg.normalCap) {
        reserve = energy - cfg.normalCap;
        energy = cfg.normalCap;
      }
    }
    final cap = (j['cap'] as num?)?.toInt();
    return EnergyState(
      game: a.game,
      accountId: a.id,
      energy: energy,
      reserve: cfg.hasReserve ? reserve.clamp(0, cfg.reserveCap!) : 0,
      cap: cap != null && cfg.capOptions.contains(cap) ? cap : null,
      updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      notifyCap: j['notifyCap'] as bool? ?? true,
    );
  }

  static EnergyState initial(Account a) => EnergyState(
        game: a.game,
        accountId: a.id,
        energy: 0,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
}

/// Pity Forecaster inputs for one account.
@immutable
class PityPlan {
  const PityPlan({
    required this.game,
    this.accountId = Account.mainId,
    this.pity = 0,
    this.guaranteed = false,
    this.currency = 0,
    this.ownedPulls = 0,
    this.dailyIncome = 60,
    this.weeklyIncome = 0,
    this.targetDateMs,
  });

  final GameId game;
  final int accountId;
  final int pity;
  final bool guaranteed;

  /// Raw premium currency (Stellar Jade / Astrite / Clear Drops / ...).
  final int currency;

  /// Pull tickets already owned (Special Passes, Radiant Tides, Unilogs...).
  final int ownedPulls;
  final int dailyIncome;
  final int weeklyIncome;
  final int? targetDateMs;

  String get key => accountKey(game, accountId);

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
        accountId: accountId,
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

  static PityPlan fromJson(Account a, Map<dynamic, dynamic> j) => PityPlan(
        game: a.game,
        accountId: a.id,
        pity: (j['pity'] as num?)?.toInt() ?? 0,
        guaranteed: j['guaranteed'] as bool? ?? false,
        currency: (j['currency'] as num?)?.toInt() ?? 0,
        ownedPulls: (j['ownedPulls'] as num?)?.toInt() ?? 0,
        dailyIncome: (j['dailyIncome'] as num?)?.toInt() ?? 60,
        weeklyIncome: (j['weeklyIncome'] as num?)?.toInt() ?? 0,
        targetDateMs: (j['targetDateMs'] as num?)?.toInt(),
      );

  static PityPlan initial(Account a) => PityPlan(game: a.game, accountId: a.id);
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
    this.multiAccountEnabled = false,
    this.accounts = const [],
    this.widgetAccounts = const {},
    this.lastAccountIds = const {},
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

  /// When off, only each game's main account is shown and alerted on; extra
  /// accounts keep their data and come back the moment the mode is re-enabled.
  final bool multiAccountEnabled;

  /// Extra accounts (id > 0), plus a main-account entry (id 0) only when the
  /// user renamed it. Use [accountsOf] rather than reading this directly.
  final List<Account> accounts;

  /// Account id shown on the home widget per game; missing = main account.
  final Map<GameId, int> widgetAccounts;

  /// Highest account id ever handed out per game. Ids are never reused, so
  /// anything still holding a removed account (an open overlay, a remembered
  /// selection) can't end up pointing at a newer one.
  final Map<GameId, int> lastAccountIds;

  bool isHidden(GameId g) => hiddenGames.contains(g);

  /// Games shown in tabs/overlay/widget, in canonical order. The settings UI
  /// refuses to hide the last visible game, so this is never empty in practice.
  List<GameId> get visibleGames =>
      [for (final g in GameId.values) if (!hiddenGames.contains(g)) g];

  /// Every account of [g]: the main account first, then extras by id.
  /// Includes extras while multi-account mode is off (their data is kept).
  List<Account> accountsOf(GameId g) {
    final main = accounts.firstWhere(
      (a) => a.game == g && a.isMain,
      orElse: () => Account(g, Account.mainId),
    );
    final extras = accounts.where((a) => a.game == g && !a.isMain).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return [main, ...extras];
  }

  /// Accounts in use for [g]: all of them in multi-account mode, else main.
  List<Account> activeAccountsOf(GameId g) {
    final all = accountsOf(g);
    return multiAccountEnabled ? all : [all.first];
  }

  /// Every account of every game, shown or not. Drives what state is loaded.
  List<Account> get allAccounts =>
      [for (final g in GameId.values) ...accountsOf(g)];

  /// Accounts shown in tabs and the overlay, grouped by game in canonical
  /// order.
  List<Account> get visibleAccounts =>
      [for (final g in visibleGames) ...activeAccountsOf(g)];

  /// Changes only when accounts are added or removed (not renamed), so
  /// state notifiers can reload exactly when the roster changes.
  String get rosterKey => allAccounts.map((a) => a.key).join(',');

  /// Whether [accountId] of [g] is shown and may fire alerts.
  bool isAccountActive(GameId g, int accountId) =>
      !isHidden(g) && activeAccountsOf(g).any((a) => a.id == accountId);

  /// True when [g] shows more than one account, so each needs a label.
  bool showsAccountLabels(GameId g) => activeAccountsOf(g).length > 1;

  Account accountOf(GameId g, int accountId) => accountsOf(g).firstWhere(
        (a) => a.id == accountId,
        orElse: () => Account(g, accountId),
      );

  /// The account whose numbers the home widget shows for [g].
  Account widgetAccountOf(GameId g) {
    final active = activeAccountsOf(g);
    final id = widgetAccounts[g] ?? Account.mainId;
    return active.firstWhere((a) => a.id == id, orElse: () => active.first);
  }

  /// Settings with a new extra account for [g]. An empty [name] becomes
  /// "Account N" (N = its position when added), so the label stays put when
  /// other accounts are removed later.
  AppSettings withAccountAdded(GameId g, String name) {
    final existing = accountsOf(g);
    final highest = max(existing.map((a) => a.id).reduce(max),
        lastAccountIds[g] ?? Account.mainId);
    final id = highest + 1;
    final label =
        name.trim().isEmpty ? 'Account ${existing.length + 1}' : name.trim();
    return copyWith(
      accounts: [...accounts, Account(g, id, label)],
      lastAccountIds: {...lastAccountIds, g: id},
    );
  }

  /// No-op when [a] was removed meanwhile (e.g. a stale dialog), so a rename
  /// can't resurrect it. Clearing an extra account's name falls back to
  /// "Account N" by position, like [withAccountAdded].
  AppSettings withAccountRenamed(Account a, String name) {
    final index = accountsOf(a.game).indexOf(a);
    if (index < 0) return this;
    final label = name.trim().isEmpty && !a.isMain
        ? 'Account ${index + 1}'
        : name.trim();
    return copyWith(accounts: [
      for (final x in accounts)
        if (x != a) x,
      a.rename(label),
    ]);
  }

  AppSettings withAccountRemoved(Account a) {
    assert(!a.isMain, 'the main account cannot be removed');
    return copyWith(
      accounts: [for (final x in accounts) if (x != a) x],
      widgetAccounts: {
        for (final e in widgetAccounts.entries)
          if (!(e.key == a.game && e.value == a.id)) e.key: e.value,
      },
    );
  }

  AppSettings withWidgetAccount(Account a) =>
      copyWith(widgetAccounts: {...widgetAccounts, a.game: a.id});

  /// [base] followed by " · " and the account label when [g] shows several
  /// accounts, e.g. "HSR · Alt". The label is looked up fresh, so renames
  /// show up even through a stale [Account].
  String withAccountLabel(String base, GameId g, int accountId) =>
      showsAccountLabels(g) ? '$base · ${accountOf(g, accountId).label}' : base;

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
    bool? multiAccountEnabled,
    List<Account>? accounts,
    Map<GameId, int>? widgetAccounts,
    Map<GameId, int>? lastAccountIds,
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        sleepSafeEnabled: sleepSafeEnabled ?? this.sleepSafeEnabled,
        sleepStartMinutes: sleepStartMinutes ?? this.sleepStartMinutes,
        sleepEndMinutes: sleepEndMinutes ?? this.sleepEndMinutes,
        summaryHour: summaryHour ?? this.summaryHour,
        burnWarningEnabled: burnWarningEnabled ?? this.burnWarningEnabled,
        hiddenGames: hiddenGames ?? this.hiddenGames,
        multiAccountEnabled: multiAccountEnabled ?? this.multiAccountEnabled,
        accounts: accounts ?? this.accounts,
        widgetAccounts: widgetAccounts ?? this.widgetAccounts,
        lastAccountIds: lastAccountIds ?? this.lastAccountIds,
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'sleepSafeEnabled': sleepSafeEnabled,
        'sleepStartMinutes': sleepStartMinutes,
        'sleepEndMinutes': sleepEndMinutes,
        'summaryHour': summaryHour,
        'burnWarningEnabled': burnWarningEnabled,
        'hiddenGames': [for (final g in hiddenGames) g.key],
        'multiAccountEnabled': multiAccountEnabled,
        'accounts': [for (final a in accounts) a.toJson()],
        'widgetAccounts': _gameIntMapToJson(widgetAccounts),
        'lastAccountIds': _gameIntMapToJson(lastAccountIds),
      };

  static Map<String, int> _gameIntMapToJson(Map<GameId, int> m) =>
      {for (final e in m.entries) e.key.key: e.value};

  static Map<GameId, int> _gameIntMapFromJson(Object? raw) {
    final byName = GameId.values.asNameMap();
    return {
      if (raw is Map)
        for (final e in raw.entries)
          if (byName[e.key] != null && e.value is num)
            byName[e.key]!: (e.value as num).toInt(),
    };
  }

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
      multiAccountEnabled: j['multiAccountEnabled'] as bool? ?? false,
      accounts: [
        for (final raw in (j['accounts'] as List? ?? const []))
          if (raw is Map) ?Account.fromJson(raw),
      ],
      widgetAccounts: _gameIntMapFromJson(j['widgetAccounts']),
      lastAccountIds: _gameIntMapFromJson(j['lastAccountIds']),
    );
  }
}
