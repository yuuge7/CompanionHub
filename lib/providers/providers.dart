import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/energy_math.dart';
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
    state = s;
    await Store.saveSettings(s);
    // Settings affect every scheduled alert -> re-plan them all.
    for (final st in ref.read(energyProvider).values) {
      await AlertScheduler.rescheduleEnergy(st, s);
    }
    await AlertScheduler.rescheduleBurnWarning(ref.read(nteWeeklyProvider), s);
    // Hidden games change what the home widget shows.
    await WidgetService.push(
        ref.read(pityPlansProvider), ref.read(energyProvider), s);
  }
}

/// Games currently shown in tabs/overlay/widget, in canonical order.
final visibleGamesProvider = Provider<List<GameId>>(
    (ref) => ref.watch(settingsProvider).visibleGames);

// ===================== Module A: Energy =====================

final energyProvider =
    NotifierProvider<EnergyNotifier, Map<GameId, EnergyState>>(
        EnergyNotifier.new);

class EnergyNotifier extends Notifier<Map<GameId, EnergyState>> {
  @override
  Map<GameId, EnergyState> build() =>
      {for (final g in GameId.values) g: Store.energy(g)};

  Future<void> setEnergy(GameId g, int value) async {
    final prev = state[g]!;
    final st = EnergyState(
      game: g,
      energy: value.clamp(0, g.config.absoluteCap),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      notifyCap: prev.notifyCap,
    );
    state = {...state, g: st};
    await Store.saveEnergy(st);
    await AlertScheduler.rescheduleEnergy(st, ref.read(settingsProvider));
    await WidgetService.push(
        ref.read(pityPlansProvider), state, ref.read(settingsProvider));
  }

  /// Applies a delta to the *projected current* value (e.g. "-60 spent").
  Future<void> adjust(GameId g, int delta) async {
    final st = state[g]!;
    final current =
        projectEnergy(g.config, st.energy, st.updatedAt, DateTime.now())
            .current;
    await setEnergy(g, current + delta);
  }

  Future<void> setNotify(GameId g, bool on) async {
    final st = state[g]!.copyWith(notifyCap: on);
    state = {...state, g: st};
    await Store.saveEnergy(st);
    await AlertScheduler.rescheduleEnergy(st, ref.read(settingsProvider));
  }
}

// ===================== Module B: Pity plans =====================

final pityPlansProvider =
    NotifierProvider<PityPlansNotifier, Map<GameId, PityPlan>>(
        PityPlansNotifier.new);

class PityPlansNotifier extends Notifier<Map<GameId, PityPlan>> {
  @override
  Map<GameId, PityPlan> build() =>
      {for (final g in GameId.values) g: Store.pityPlan(g)};

  Future<void> update(PityPlan p) async {
    state = {...state, p.game: p};
    await Store.savePityPlan(p);
    // keep the home widget in sync
    await WidgetService.push(
        state, ref.read(energyProvider), ref.read(settingsProvider));
  }

  Future<void> pushWidget() => WidgetService.push(
      state, ref.read(energyProvider), ref.read(settingsProvider));
}

// ===================== Module C: Daily tasks =====================

/// State maps `<game>:<taskIndex>` -> checkedAt epoch ms. A task counts as
/// checked only if its timestamp is after the game's last daily reset, so
/// items "uncheck themselves" at server reset with zero background work.
final tasksProvider =
    NotifierProvider<TasksNotifier, Map<String, int>>(TasksNotifier.new);

class TasksNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => _readAll();

  Map<String, int> _readAll() {
    final map = <String, int>{};
    for (final g in GameId.values) {
      for (var i = 0; i < g.config.dailyTasks.length; i++) {
        final ms = Store.taskCheckedAtMs(g, i);
        if (ms != null) map['${g.key}:$i'] = ms;
      }
    }
    return map;
  }

  bool isChecked(GameId g, int index, DateTime now) {
    final ms = state['${g.key}:$index'];
    if (ms == null) return false;
    return ms >= lastDailyReset(g.config.dailyResetHour, now)
        .millisecondsSinceEpoch;
  }

  Future<void> toggle(GameId g, int index, bool checked) async {
    await Store.setTaskChecked(g, index, checked);
    final key = '${g.key}:$index';
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
    state = _readAll();
  }
}

// ===================== NTE weekly dashboard =====================

final nteWeeklyProvider =
    NotifierProvider<NteWeeklyNotifier, NteWeeklyState>(NteWeeklyNotifier.new);

class NteWeeklyNotifier extends Notifier<NteWeeklyState> {
  @override
  NteWeeklyState build() {
    final stored = Store.nteWeekly();
    final weekStart = lastWeeklyReset(
      kNteWeeklyResetWeekday,
      kNteWeeklyResetHour,
      DateTime.now(),
    ).millisecondsSinceEpoch;

    if (stored.weekStartMs == weekStart) return stored;

    // New week -> wipe the checklist, keep the tycoon level.
    final fresh = stored.copyWith(
      done: List.filled(kNteWeeklyTasks.length, false),
      weekStartMs: weekStart,
    );
    Future.microtask(() async {
      await Store.saveNteWeekly(fresh);
      await AlertScheduler.rescheduleBurnWarning(
          fresh, ref.read(settingsProvider));
    });
    return fresh;
  }

  Future<void> setTycoonLevel(int level) async {
    state = state.copyWith(tycoonLevel: level.clamp(1, 60));
    await Store.saveNteWeekly(state);
  }

  Future<void> toggleTask(int index, bool value) async {
    final done = [...state.done];
    done[index] = value;
    state = state.copyWith(done: done);
    await Store.saveNteWeekly(state);
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
