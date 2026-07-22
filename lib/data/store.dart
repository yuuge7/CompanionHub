import 'package:hive_flutter/hive_flutter.dart';

import '../core/games.dart';
import 'models.dart';

/// Thin Hive wrapper. Everything is stored as plain JSON maps so no code
/// generation (TypeAdapters / build_runner) is required.
///
/// NOTE on the overlay: the floating bubble runs in a second FlutterEngine in
/// the same process and opens these boxes too. Writers always flush(), and the
/// main app reloads on lifecycle resume + on overlay "tasks_changed" pings, so
/// both sides stay consistent.
class Store {
  Store._();

  static const _energyBox = 'energy';
  static const _pityBox = 'pity';
  static const _tasksBox = 'tasks';
  static const _nteBox = 'nte';
  static const _settingsBox = 'settings';

  static late Box _energy;
  static late Box _pity;
  static late Box _tasks;
  static late Box _nte;
  static late Box _settings;

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    _energy = await Hive.openBox(_energyBox);
    _pity = await Hive.openBox(_pityBox);
    _tasks = await Hive.openBox(_tasksBox);
    _nte = await Hive.openBox(_nteBox);
    _settings = await Hive.openBox(_settingsBox);
    _ready = true;
  }

  // ---- Energy ----
  static EnergyState energy(GameId g) {
    final raw = _energy.get(g.key);
    if (raw is Map) return EnergyState.fromJson(g, raw);
    return EnergyState.initial(g);
  }

  static Future<void> saveEnergy(EnergyState s) async {
    await _energy.put(s.game.key, s.toJson());
    await _energy.flush();
  }

  // ---- Pity plans ----
  static PityPlan pityPlan(GameId g) {
    final raw = _pity.get(g.key);
    if (raw is Map) return PityPlan.fromJson(g, raw);
    return PityPlan(game: g);
  }

  static Future<void> savePityPlan(PityPlan p) async {
    await _pity.put(p.game.key, p.toJson());
    await _pity.flush();
  }

  // ---- Daily tasks: key "<game>:<index>" -> checkedAt epoch ms ----
  static String _taskKey(GameId g, int index) => '${g.key}:$index';

  static int? taskCheckedAtMs(GameId g, int index) {
    final v = _tasks.get(_taskKey(g, index));
    return v is int ? v : null;
  }

  static Future<void> setTaskChecked(GameId g, int index, bool checked) async {
    if (checked) {
      await _tasks.put(_taskKey(g, index), DateTime.now().millisecondsSinceEpoch);
    } else {
      await _tasks.delete(_taskKey(g, index));
    }
    await _tasks.flush();
  }

  /// Re-reads task state from disk (used after the overlay wrote changes).
  static Future<void> reloadTasks() async {
    await _tasks.close();
    _tasks = await Hive.openBox(_tasksBox);
  }

  /// Re-reads settings from disk (used by the overlay engine to pick up
  /// hidden-game changes written by the main app while the bubble is alive).
  static Future<void> reloadSettings() async {
    await _settings.close();
    _settings = await Hive.openBox(_settingsBox);
  }

  // ---- NTE weekly ----
  static NteWeeklyState nteWeekly() {
    final raw = _nte.get('weekly');
    if (raw is Map) return NteWeeklyState.fromJson(raw);
    return NteWeeklyState.initial();
  }

  static Future<void> saveNteWeekly(NteWeeklyState s) async {
    await _nte.put('weekly', s.toJson());
    await _nte.flush();
  }

  // ---- Settings ----
  static AppSettings settings() {
    final raw = _settings.get('app');
    if (raw is Map) return AppSettings.fromJson(raw);
    return const AppSettings();
  }

  static Future<void> saveSettings(AppSettings s) async {
    await _settings.put('app', s.toJson());
    await _settings.flush();
  }
}
