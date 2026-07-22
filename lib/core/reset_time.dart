/// Daily / weekly server-reset helpers. All computations use the device's
/// local time zone; per-game reset hours live in GameConfig.
library;

DateTime lastDailyReset(int resetHour, DateTime now) {
  var reset = DateTime(now.year, now.month, now.day, resetHour);
  if (reset.isAfter(now)) reset = reset.subtract(const Duration(days: 1));
  return reset;
}

DateTime nextDailyReset(int resetHour, DateTime now) =>
    lastDailyReset(resetHour, now).add(const Duration(days: 1));

/// Most recent occurrence of [weekday] (DateTime.monday..sunday) at [hour].
DateTime lastWeeklyReset(int weekday, int hour, DateTime now) {
  var candidate = DateTime(now.year, now.month, now.day, hour);
  while (candidate.weekday != weekday || candidate.isAfter(now)) {
    candidate = candidate.subtract(const Duration(days: 1));
  }
  return candidate;
}

DateTime nextWeeklyReset(int weekday, int hour, DateTime now) =>
    lastWeeklyReset(weekday, hour, now).add(const Duration(days: 7));

/// Next occurrence of [weekday] at [hour] strictly after [now]
/// (e.g. the upcoming Sunday-evening burn warning slot).
DateTime nextWeekdayTime(int weekday, int hour, DateTime now) {
  var candidate = DateTime(now.year, now.month, now.day, hour);
  while (candidate.weekday != weekday || !candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

String formatDuration(Duration d) {
  if (d.isNegative) return 'now';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final mins = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}
