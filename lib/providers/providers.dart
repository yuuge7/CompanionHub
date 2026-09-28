import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/alert_scheduler.dart';
import '../services/widget_service.dart';

/// 1-second ticker driving live countdowns and energy projections.
/// Built on an explicit Timer (not Stream.periodic) so the timer is
/// deterministically cancelled when the container is disposed.
final clockProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  final timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => controller.add(DateTime.now()),
  );
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

// ===================== Settings =====================

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => Store.settings();

  Future<void> update(AppSettings s) async {
    final rosterChanged = s.rosterKey != state.rosterKey;
    state = s;
    await Store.saveSettings(s);
    if (rosterChanged) {
      // Per-account notifiers *read* the roster instead of watching it:
      // update() reads them to re-plan alerts, and Riverpod rejects reading a
      // provider that watches you (CircularDependencyError). Rebuild them by
      // hand now that an account was added or removed.
      ref
        ..invalidate(energyProvider)
        ..invalidate(pityPlansProvider)
        ..invalidate(tasksProvider)
        ..invalidate(nteWeeklyProvider);
    }
    // Settings affect every scheduled alert -> re-plan them all. This covers
    // every stored account, so accounts that just became inactive (hidden
    // game, multi-account mode off) get their alerts cancelled too.
    for (final st in ref.read(energyProvider).values) {
      await AlertScheduler.rescheduleEnergy(st, s);
    }
    await AlertScheduler.rescheduleBurnWarning(ref.read(nteWeeklyProvider), s);
    // Hidden games / widget accounts change what the home widget shows.
    await WidgetService.push(
        ref.read(pityPlansProvider), ref.read(energyProvider), s);
  }

  Future<void> addAccount(GameId g, String name) =>
      update(state.withAccountAdded(g, name));

  Future<void> renameAccount(Account a, String name) =>
      update(state.withAccountRenamed(a, name));

  /// Deletes [a] and everything stored for it. The main account can't be
  /// removed.
  Future<void> removeAccount(Account a) async {
    if (a.isMain) return;
    // The account leaves the roster below, so the blanket re-plan in update()
    // no longer sees it: cancel its alerts explicitly first.
    await AlertScheduler.cancelEnergy(a.game, a.id);
    await Store.deleteAccountData(a);
    await update(state.withAccountRemoved(a));
  }

  Future<void> setWidgetAccount(Account a) =>
      update(state.withWidgetAccount(a));
}

/// Games currently shown in tabs/overlay/widget, in canonical order.
final visibleGamesProvider = Provider<List<GameId>>(
    (ref) => ref.watch(settingsProvider).visibleGames);

/// Accounts currently shown in tabs/overlay, grouped by game.
final visibleAccountsProvider = Provider<List<Account>>(
    (ref) => ref.watch(settingsProvider).visibleAccounts);


// ===================== Module A: Energy =====================

/// Energy anchors keyed by [Account.key].
final energyProvider =
    NotifierProvider<EnergyNotifier, Map<String, EnergyState>>(
        EnergyNotifier.new);

class EnergyNotifier extends Notifier<Map<String, EnergyState>> {
  @override
  Map<String, EnergyState> build() =>
      {for (final a in ref.read(settingsProvider).allAccounts) a.key: Store.energy(a)};

  EnergyState of(Account a) => state[a.key] ?? EnergyState.initial(a);

  /// Re-anchors [a] at the current time. Values left out keep their
  /// projected current value, so e.g. editing the main pool doesn't lose the
  /// reserve that accrued since the last update.
  Future<void> setEnergy(
    Account a, {
    int? energy,
    int? reserve,
    int? cap,
  }) async {
    final now = DateTime.now();
    final prev = of(a);
    final snap = prev.projectAt(now);
    final cfg = a.game.config;
    final st = prev.copyWith(
      energy: (energy ?? snap.current).clamp(0, kEnergyInputLimit),
      reserve: cfg.hasReserve
          ? (reserve ?? snap.reserve).clamp(0, cfg.reserveCap!)
          : 0,
      cap: cap,
      updatedAtMs: now.millisecondsSinceEpoch,
    );
    state = {...state, a.key: st};
    await Store.saveEnergy(st);
    await AlertScheduler.rescheduleEnergy(st, ref.read(settingsProvider));
    await WidgetService.push(
        ref.read(pityPlansProvider), state, ref.read(settingsProvider));
  }

  /// Applies a delta to the *projected current* main pool (e.g. "-60
  /// spent"); the reserve is untouched, as in-game.
  Future<void> adjust(Account a, int delta) async {
    final current = of(a).projectAt(DateTime.now()).current;
    await setEnergy(a, energy: current + delta);
  }

  Future<void> setNotify(Account a, bool on) async {
    final st = of(a).copyWith(notifyCap: on);
    state = {...state, a.key: st};
    await Store.saveEnergy(st);
    await AlertScheduler.rescheduleEnergy(st, ref.read(settingsProvider));
  }
}

// ===================== Module B: Pity plans =====================

/// Pity plans keyed by [Account.key].
final pityPlansProvider =
    NotifierProvider<PityPlansNotifier, Map<String, PityPlan>>(
        PityPlansNotifier.new);

class PityPlansNotifier extends Notifier<Map<String, PityPlan>> {
  @override
  Map<String, PityPlan> build() => {
        for (final a in ref.read(settingsProvider).allAccounts) a.key: Store.pityPlan(a)
      };

  PityPlan of(Account a) => state[a.key] ?? PityPlan.initial(a);

  Future<void> update(PityPlan p) async {
    state = {...state, p.key: p};
    await Store.savePityPlan(p);
    // keep the home widget in sync
    await WidgetService.push(
        state, ref.read(energyProvider), ref.read(settingsProvider));
  }

  Future<void> pushWidget() => WidgetService.push(
      state, ref.read(energyProvider), ref.read(settingsProvider));
}

// ===================== Module C: Daily tasks =====================

/// State maps `<account key>:<taskIndex>` -> checkedAt epoch ms. A task counts
/// as checked only if its timestamp is after the game's last daily reset, so
/// items "uncheck themselves" at server reset with zero background work.
final tasksProvider =
    NotifierProvider<TasksNotifier, Map<String, int>>(TasksNotifier.new);

class TasksNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => _readAll(ref.read(settingsProvider).allAccounts);

  Map<String, int> _readAll(List<Account> accounts) {
    final map = <String, int>{};
    for (final a in accounts) {
      for (var i = 0; i < a.game.config.dailyTasks.length; i++) {
        final ms = Store.taskCheckedAtMs(a, i);
        if (ms != null) map[Store.taskKey(a, i)] = ms;
      }
    }
    return map;
  }

  bool isChecked(Account a, int index, DateTime now) {
    final ms = state[Store.taskKey(a, index)];
    if (ms == null) return false;
    return ms >= lastDailyReset(a.game.config.reset, now)
        .millisecondsSinceEpoch;
  }

  Future<void> toggle(Account a, int index, bool checked) async {
    await Store.setTaskChecked(a, index, checked);
    final key = Store.taskKey(a, index);
    final next = {...state};
    if (checked) {
      next[key] = DateTime.now().millisecondsSinceEpoch;
    } else {
      next.remove(key);
    }
    state = next;
  }

  /// Reload from disk after the overlay bubble wrote changes.
  Future<void> reload() async {
    await Store.reloadTasks();
    state = _readAll(ref.read(settingsProvider).allAccounts);
  }
}

// ===================== NTE weekly dashboard =====================

/// NTE weekly state keyed by [Account.key] (NTE accounts only).
final nteWeeklyProvider =
    NotifierProvider<NteWeeklyNotifier, Map<String, NteWeeklyState>>(
        NteWeeklyNotifier.new);

class NteWeeklyNotifier extends Notifier<Map<String, NteWeeklyState>> {
  static int _currentWeekStart() => lastWeeklyReset(
        kNteWeeklyResetWeekday,
        GameId.nte.config.reset,
        DateTime.now(),
      ).millisecondsSinceEpoch;

  @override
  Map<String, NteWeeklyState> build() {
    final weekStart = _currentWeekStart();

    final out = <String, NteWeeklyState>{};
    final rolled = <Account, NteWeeklyState>{};
    for (final a in ref.read(settingsProvider).allAccounts) {
      if (a.game != GameId.nte) continue;
      final stored = Store.nteWeekly(a);
      if (stored.weekStartMs == weekStart) {
        out[a.key] = stored;
        continue;
      }
      // Older versions anchored the week at Monday 05:00 device time rather
      // than server time: an anchor less than a day off is this week, just
      // re-anchored. Otherwise it's a new week -> wipe the checklist, keep
      // the tycoon level.
      final sameWeek = (stored.weekStartMs - weekStart).abs() <
          const Duration(days: 1).inMilliseconds;
      out[a.key] = rolled[a] = stored.copyWith(
        done: sameWeek ? null : List.filled(kNteWeeklyTasks.length, false),
        weekStartMs: weekStart,
      );
    }

    if (rolled.isNotEmpty) {
      Future.microtask(() async {
        for (final e in rolled.entries) {
          await Store.saveNteWeekly(e.key, e.value);
        }
        await AlertScheduler.rescheduleBurnWarning(
            state, ref.read(settingsProvider));
      });
    }
    return out;
  }

  /// Falls back to a blank state for *this* week, so edits made through it
  /// aren't wiped as last week's on the next build.
  NteWeeklyState of(Account a) =>
      state[a.key] ??
      NteWeeklyState.initial().copyWith(weekStartMs: _currentWeekStart());

  Future<void> setTycoonLevel(Account a, int level) async {
    final st =
        of(a).copyWith(tycoonLevel: level.clamp(1, kNteMaxTycoonLevel));
    state = {...state, a.key: st};
    await Store.saveNteWeekly(a, st);
  }

  Future<void> toggleTask(Account a, int index, bool value) async {
    final done = [...of(a).done];
    done[index] = value;
    final st = of(a).copyWith(done: done);
    state = {...state, a.key: st};
    await Store.saveNteWeekly(a, st);
    await AlertScheduler.rescheduleBurnWarning(
        state, ref.read(settingsProvider));
  }
}

// ===================== Startup re-scheduling =====================

/// Re-plans every alert from persisted state; call once on app launch so
/// alarms survive reinstalls/reboots even before the boot receiver kicks in.
Future<void> rescheduleAllAlerts(Ref ref) async {
  final settings = ref.read(settingsProvider);
  for (final st in ref.read(energyProvider).values) {
    await AlertScheduler.rescheduleEnergy(st, settings);
  }
  await AlertScheduler.rescheduleBurnWarning(
      ref.read(nteWeeklyProvider), settings);
}

final startupProvider = FutureProvider<void>((ref) async {
  await rescheduleAllAlerts(ref);
  await WidgetService.push(ref.read(pityPlansProvider),
      ref.read(energyProvider), ref.read(settingsProvider));
});
