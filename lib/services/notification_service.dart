import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local-notification plumbing. All scheduling is offline via AlarmManager;
/// no Firebase / network involved.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification id ranges (one per game where applicable):
  //   100 + game.index : energy cap warning
  //   200 + game.index : silent overnight summary
  //   300              : NTE weekly burn warning
  static int capWarnId(int gameIndex) => 100 + gameIndex;
  static int summaryId(int gameIndex) => 200 + gameIndex;
  static const int burnWarningId = 300;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      // flutter_timezone >=5 returns a TimezoneInfo, older versions a String.
      final dynamic local = await FlutterTimezone.getLocalTimezone();
      final name = local is String ? local : (local.identifier as String);
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // tz.local stays UTC — scheduled *instants* remain correct because we
      // always convert concrete DateTimes, never wall-clock recurrences.
      debugPrint('Timezone detection failed: $e');
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    } catch (e) {
      // Notifications become no-ops; timers/pity/tasks must keep working.
      debugPrint('Notification plugin init failed: $e');
    }
  }

  Future<bool> requestPermissions() async {
    if (!_initialized) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      final notifGranted =
          await android.requestNotificationsPermission() ?? false;
      final exactAllowed =
          await android.canScheduleExactNotifications() ?? false;
      if (!exactAllowed) {
        await android.requestExactAlarmsPermission();
      }
      return notifGranted;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  AndroidNotificationDetails _details({required bool silent}) {
    if (silent) {
      return const AndroidNotificationDetails(
        'silent_summaries',
        'Silent summaries',
        channelDescription:
            'Quiet morning recaps produced by the Sleep Safe setting.',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        category: AndroidNotificationCategory.status,
      );
    }
    return const AndroidNotificationDetails(
      'energy_alerts',
      'Energy & weekly alerts',
      channelDescription:
          'Cap warnings and weekly burn warnings for tracked games.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
  }

  /// Schedules a one-shot notification at [when] (device-local instant).
  /// Falls back to inexact scheduling if exact alarms are not permitted.
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    bool silent = false,
  }) async {
    if (!_initialized) return;
    if (!when.isAfter(DateTime.now())) return;
    final tzWhen = tz.TZDateTime.from(when, tz.local);
    final details = NotificationDetails(android: _details(silent: silent));
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzWhen,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Exact alarm rejected ($e); falling back to inexact.');
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: tzWhen,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('Scheduling failed entirely: $e');
      }
    }
  }

  Future<void> cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('Notification cancel failed: $e');
    }
  }
}
