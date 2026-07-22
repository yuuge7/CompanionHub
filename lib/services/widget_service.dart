import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../core/games.dart';
import '../data/models.dart';

/// Pushes currency-to-pulls data into the native Android home screen widget.
/// Keys must match PullWidgetProvider.kt. `vis_<game>` ("1"/"0") tells the
/// provider whether the game's row should be shown at all.
///
/// Energy is pushed as an *anchor* (value + timestamp) together with the
/// regen rates; the Kotlin provider projects it forward on every periodic
/// widget update, so numbers stay fresh without waking the Flutter engine.
class WidgetService {
  WidgetService._();

  static final _compact = NumberFormat.compact();

  static Future<void> push(
    Map<GameId, PityPlan> plans,
    Map<GameId, EnergyState> energy,
    AppSettings settings,
  ) async {
    for (final g in GameId.values) {
      final plan = plans[g] ?? PityPlan(game: g);
      final cfg = g.config;
      final pulls = plan.ownedPulls + plan.currency ~/ cfg.pullCost;
      final st = energy[g] ?? EnergyState.initial(g);
      await HomeWidget.saveWidgetData<String>(
          'vis_${g.key}', settings.isHidden(g) ? '0' : '1');
      await HomeWidget.saveWidgetData<String>(
          'cur_${g.key}', _compact.format(plan.currency));
      await HomeWidget.saveWidgetData<String>('pulls_${g.key}', '$pulls');
      await HomeWidget.saveWidgetData<String>(
          'eanchor_${g.key}', '${st.energy}');
      await HomeWidget.saveWidgetData<String>(
          'eanchorms_${g.key}', '${st.updatedAtMs}');
      await HomeWidget.saveWidgetData<String>(
          'ecap_${g.key}', '${cfg.normalCap}');
      await HomeWidget.saveWidgetData<String>(
          'erate_${g.key}', '${cfg.normalRateMinutes}');
      await HomeWidget.saveWidgetData<String>(
          'eocap_${g.key}', '${cfg.overflowCap ?? 0}');
      await HomeWidget.saveWidgetData<String>(
          'eorate_${g.key}', '${cfg.overflowRateMinutes ?? 0}');
    }
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.companionhub.companion_hub.PullWidgetProvider',
    );
  }
}
