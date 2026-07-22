import 'package:intl/intl.dart';

import '../core/energy_math.dart';
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

  /// Re-plans the cap warning (or Sleep Safe silent summary) for one game.
  static Future<void> rescheduleEnergy(
    EnergyState st,
    AppSettings settings,
  ) async {
    final g = st.game.config;
    final ns = NotificationService.instance;
    await ns.cancel(NotificationService.capWarnId(st.game.index));
    await ns.cancel(NotificationService.summaryId(st.game.index));

    if (!settings.notificationsEnabled ||
        !st.notifyCap ||
        settings.isHidden(st.game)) {
      return;
    }

    final now = DateTime.now();
    final snap = projectEnergy(g, st.energy, st.updatedAt, now);
    final capAt = snap.normalCapAt;
    if (capAt == null) return; // already at/above normal cap

    // Sleep Safe: cap lands inside the quiet window -> suppress the alarm,
    // deliver a silent morning summary with the overnight overflow instead.
    if (settings.sleepSafeEnabled && settings.isAsleep(capAt)) {
      final summaryAt = settings.nextSummaryTime(capAt);
      final morning = projectEnergy(g, st.energy, st.updatedAt, summaryAt);
      final body = g.hasOverflow
          ? '${g.energyName} capped at ${_fmtTime(capAt)} while you slept. '
              '${morning.overflowPortion} overflow banked overnight '
              '(${morning.current}/${g.absoluteCap}).'
          : '${g.energyName} capped at ${_fmtTime(capAt)} while you slept — '
              'regeneration has been idle since.';
      await ns.scheduleAt(
        id: NotificationService.summaryId(st.game.index),
        title: '${g.shortName}: overnight cap summary',
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
    final tail = g.hasOverflow
        ? 'after that it only trickles into the slow overflow reserve.'
        : 'after that regeneration stops.';
    await ns.scheduleAt(
      id: NotificationService.capWarnId(st.game.index),
      title: '${g.shortName}: ${g.energyName} nearly full',
      body: 'Hits ${g.normalCap} at ${_fmtTime(capAt)} — $tail',
      when: fireAt,
    );
  }

  /// NTE burn warning: Sunday evening ping while weekly limits are unfinished.
  static Future<void> rescheduleBurnWarning(
    NteWeeklyState s,
    AppSettings settings,
  ) async {
    final ns = NotificationService.instance;
    await ns.cancel(NotificationService.burnWarningId);

    if (!settings.notificationsEnabled ||
        !settings.burnWarningEnabled ||
        settings.isHidden(GameId.nte) ||
        s.allDone) {
      return;
    }

    final now = DateTime.now();
    final fireAt =
        nextWeekdayTime(DateTime.sunday, kNteBurnWarningHour, now);
    final remaining = [
      for (var i = 0; i < kNteWeeklyTasks.length; i++)
        if (!s.done[i]) kNteWeeklyTasks[i],
    ].join(', ');

    await ns.scheduleAt(
      id: NotificationService.burnWarningId,
      title: 'NTE: weekly limits reset Monday 05:00',
      body: 'Still unfinished: $remaining. Burn them before the reset!',
      when: fireAt,
    );
  }
}
