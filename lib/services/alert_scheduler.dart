import 'package:intl/intl.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../data/models.dart';
import 'notification_service.dart';

/// Turns app state into concrete scheduled notifications.
/// Called whenever energy, NTE weekly state or settings change.
class AlertScheduler {
  AlertScheduler._();

  static String _fmtTime(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay
        ? DateFormat('HH:mm').format(t)
        : DateFormat('EEE HH:mm').format(t);
  }

  /// Cancels both energy alerts (cap warning + summary) of one account.
  static Future<void> cancelEnergy(GameId game, int accountId) async {
    final ns = NotificationService.instance;
    await ns.cancel(NotificationService.capWarnId(game.index, accountId));
    await ns.cancel(NotificationService.summaryId(game.index, accountId));
  }

  /// Re-plans the cap warning (or Sleep Safe silent summary) for one account.
  static Future<void> rescheduleEnergy(
    EnergyState st,
    AppSettings settings,
  ) async {
    final g = st.game.config;
    final ns = NotificationService.instance;
    await cancelEnergy(st.game, st.accountId);

    if (!settings.notificationsEnabled ||
        !st.notifyCap ||
        !settings.isAccountActive(st.game, st.accountId)) {
      return;
    }

    final now = DateTime.now();
    final snap = st.projectAt(now);
    final capAt = snap.capAt;
    if (capAt == null) return; // already at/above normal cap
    // "HSR", or "HSR · Alt" when the game shows several accounts.
    final prefix =
        settings.withAccountLabel(g.shortName, st.game, st.accountId);

    // Sleep Safe: cap lands inside the quiet window -> suppress the alarm,
    // deliver a silent morning summary with the overnight reserve instead.
    if (settings.sleepSafeEnabled && settings.isAsleep(capAt)) {
      final summaryAt = settings.nextSummaryTime(capAt);
      final morning = st.projectAt(summaryAt);
      final banked = morning.reserve - st.projectAt(capAt).reserve;
      final body = g.hasReserve
          ? '${g.energyName} capped at ${_fmtTime(capAt)} while you slept. '
              '$banked banked overnight in ${g.reserveName} '
              '(${morning.reserve}/${g.reserveCap}).'
          : '${g.energyName} capped at ${_fmtTime(capAt)} while you slept — '
              'regeneration has been idle since.';
      await ns.scheduleAt(
        id: NotificationService.summaryId(st.game.index, st.accountId),
        title: '$prefix: overnight cap summary',
        body: body,
        when: summaryAt,
        silent: true,
      );
      return;
    }

    // Normal path: warn 30 minutes ahead (or ASAP if we're inside the window).
    final warnAt = capAt.subtract(const Duration(minutes: 30));
    final fireAt =
        warnAt.isAfter(now) ? warnAt : now.add(const Duration(minutes: 1));
    if (!fireAt.isBefore(capAt)) return;
    final tail = g.hasReserve
        ? 'after that it only trickles into ${g.reserveName}.'
        : 'after that regeneration stops.';
    await ns.scheduleAt(
      id: NotificationService.capWarnId(st.game.index, st.accountId),
      title: '$prefix: ${g.energyName} nearly full',
      body: 'Hits ${snap.cap} at ${_fmtTime(capAt)} — $tail',
      when: fireAt,
    );
  }

  /// NTE burn warning: one Sunday-evening ping covering every active NTE
  /// account whose weekly limits are unfinished. [weeklies] is keyed by
  /// [Account.key].
  static Future<void> rescheduleBurnWarning(
    Map<String, NteWeeklyState> weeklies,
    AppSettings settings,
  ) async {
    final ns = NotificationService.instance;
    await ns.cancel(NotificationService.burnWarningId);

    if (!settings.notificationsEnabled ||
        !settings.burnWarningEnabled ||
        settings.isHidden(GameId.nte)) {
      return;
    }

    final labelled = settings.showsAccountLabels(GameId.nte);
    final lines = [
      for (final a in settings.activeAccountsOf(GameId.nte))
        if (weeklies[a.key] case final s? when !s.allDone)
          (labelled ? '${a.label}: ' : '') +
              [
                for (var i = 0; i < kNteWeeklyTasks.length; i++)
                  if (!s.done[i]) kNteWeeklyTasks[i],
              ].join(', '),
    ];
    if (lines.isEmpty) return;

    final now = DateTime.now();
    final fireAt =
        nextWeekdayTime(DateTime.sunday, kNteBurnWarningHour, now);
    final resetAt = nextWeeklyReset(
        kNteWeeklyResetWeekday, GameId.nte.config.reset, fireAt);

    await ns.scheduleAt(
      id: NotificationService.burnWarningId,
      title: 'NTE: weekly limits reset ${_fmtTime(resetAt)}',
      body: 'Still unfinished — ${lines.join('; ')}. '
          'Burn them before the reset!',
      when: fireAt,
    );
  }
}
