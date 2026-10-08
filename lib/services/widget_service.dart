import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../core/games.dart';
import '../data/models.dart';

/// Pushes currency-to-pulls data into the native Android home screen widget.
/// Keys must match PullWidgetProvider.kt. `vis_<game>` ("1"/"0") tells the
/// provider whether the game's row should be shown at all; `acct_<game>` is
/// the label of the account shown, a game's only account included.
///
/// Energy is pushed as an *anchor* (main pool + reserve + timestamp) together
/// with the account's cap and the regen rates; the Kotlin provider projects it forward on every periodic
/// widget update, so numbers stay fresh without waking the Flutter engine.
class WidgetService {
  WidgetService._();

  static final _compact = NumberFormat.compact();

  /// [plans] and [energy] are keyed by [Account.key]; each game's row shows
  /// the account picked by [AppSettings.widgetAccountOf].
  static Future<void> push(
    Map<String, PityPlan> plans,
    Map<String, EnergyState> energy,
    AppSettings settings,
  ) async {
    for (final g in GameId.values) {
      final account = settings.widgetAccountOf(g);
      final plan = plans[account.key] ?? PityPlan.initial(account);
      final cfg = g.config;
      final pulls = plan.ownedPulls + plan.currency ~/ cfg.pullCost;
      final st = energy[account.key] ?? EnergyState.initial(account);
      await HomeWidget.saveWidgetData<String>(
          'vis_${g.key}', settings.isHidden(g) ? '0' : '1');
      await HomeWidget.saveWidgetData<String>('acct_${g.key}', account.label);
      await HomeWidget.saveWidgetData<String>(
          'cur_${g.key}', _compact.format(plan.currency));
      await HomeWidget.saveWidgetData<String>('pulls_${g.key}', '$pulls');
      await HomeWidget.saveWidgetData<String>(
          'eanchor_${g.key}', '${st.energy}');
      await HomeWidget.saveWidgetData<String>(
          'eres_${g.key}', '${st.reserve}');
      await HomeWidget.saveWidgetData<String>(
          'eanchorms_${g.key}', '${st.updatedAtMs}');
      await HomeWidget.saveWidgetData<String>(
          'ecap_${g.key}', '${st.effectiveCap}');
      await HomeWidget.saveWidgetData<String>(
          'erate_${g.key}', '${cfg.normalRateMinutes}');
      await HomeWidget.saveWidgetData<String>(
          'erescap_${g.key}', '${cfg.reserveCap ?? 0}');
      await HomeWidget.saveWidgetData<String>(
          'eresrate_${g.key}', '${cfg.reserveRateMinutes ?? 0}');
    }
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.companionhub.companion_hub.PullWidgetProvider',
    );
  }
}
