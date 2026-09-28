/// Daily / weekly server-reset helpers. Resets are defined on each game's
/// server clock (see GameConfig.reset) and returned as device-local instants,
/// so they stay correct across daylight-saving switches and time zones.
library;

/// A game's server reset: [hour]:00 on a server clock that runs at a fixed
/// [utcOffsetHours]. Game servers don't observe daylight saving time, so the
/// reset is the same UTC instant all year even though the device-local hour
/// shifts (e.g. 04:00 UTC+1 is 06:00 in Bucharest in summer, 05:00 in winter).
class ServerReset {
  const ServerReset(this.hour, this.utcOffsetHours);

  final int hour;
  final int utcOffsetHours;

  Duration get _offset => Duration(hours: utcOffsetHours);

  /// [now] expressed as the server's wall clock, stored in a UTC DateTime so
  /// date arithmetic on it never meets a DST jump.
  DateTime _serverClock(DateTime now) => now.toUtc().add(_offset);

  /// Converts a server wall-clock time back to a device-local instant.
  DateTime _local(DateTime serverClock) =>
      serverClock.subtract(_offset).toLocal();

  /// e.g. "04:00 UTC+1".
  String get label {
    final sign = utcOffsetHours < 0 ? '-' : '+';
    return '${hour.toString().padLeft(2, '0')}:00 UTC$sign${utcOffsetHours.abs()}';
  }
}

DateTime lastDailyReset(ServerReset r, DateTime now) {
  final s = r._serverClock(now);
  var reset = DateTime.utc(s.year, s.month, s.day, r.hour);
  if (reset.isAfter(s)) reset = reset.subtract(const Duration(days: 1));
  return r._local(reset);
}

DateTime nextDailyReset(ServerReset r, DateTime now) =>
    lastDailyReset(r, now).add(const Duration(days: 1));

/// Most recent reset on [weekday] (DateTime.monday..sunday, server calendar).
DateTime lastWeeklyReset(int weekday, ServerReset r, DateTime now) {
  final s = r._serverClock(now);
  var candidate = DateTime.utc(s.year, s.month, s.day, r.hour);
  while (candidate.weekday != weekday || candidate.isAfter(s)) {
    candidate = candidate.subtract(const Duration(days: 1));
  }
  return r._local(candidate);
}

DateTime nextWeeklyReset(int weekday, ServerReset r, DateTime now) =>
    lastWeeklyReset(weekday, r, now).add(const Duration(days: 7));

/// Next occurrence of [weekday] at local [hour] strictly after [now]
/// (e.g. the upcoming Sunday-evening burn warning slot).
DateTime nextWeekdayTime(int weekday, int hour, DateTime now) {
  var candidate = DateTime(now.year, now.month, now.day, hour);
  while (candidate.weekday != weekday || !candidate.isAfter(now)) {
    candidate = DateTime(candidate.year, candidate.month, candidate.day + 1, hour);
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
