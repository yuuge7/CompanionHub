import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Controls the floating daily-task bubble (Module C).
class OverlayService {
  OverlayService._();

  static Stream<dynamic>? _events;

  /// Messages sent by the overlay engine (e.g. 'tasks_changed').
  ///
  /// The plugin's [FlutterOverlayWindow.overlayListener] is a static
  /// single-subscription stream: listening to it twice in the same isolate
  /// (any HomeShell remount) throws "Stream has already been listened to"
  /// and kills the whole widget tree. Expose it once as a broadcast stream.
  static Stream<dynamic> get events =>
      _events ??= FlutterOverlayWindow.overlayListener.asBroadcastStream();

  /// Logical sizes; converted to physical pixels with the device pixel ratio
  /// because the Android WindowManager works in raw pixels.
  static const double collapsedDp = 68;
  static const double expandedWidthDp = 300;
  static const double expandedHeightDp = 420;

  static Future<bool> isPermissionGranted() =>
      FlutterOverlayWindow.isPermissionGranted();

  static Future<bool> requestPermission() async =>
      await FlutterOverlayWindow.requestPermission() ?? false;

  static Future<bool> isActive() => FlutterOverlayWindow.isActive();

  static Future<void> show(double devicePixelRatio) async {
    if (await FlutterOverlayWindow.isActive()) return;
    // showOverlay expects raw pixels (unlike resizeOverlay, which takes dp).
    final px = (collapsedDp * devicePixelRatio).round();
    await FlutterOverlayWindow.showOverlay(
      height: px,
      width: px,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      // PositionGravity.auto computes its snap destination in top-left
      // coordinates; with a centerRight-anchored window that animates the
      // bubble toward garbage positions after every drag (violent jitter).
      // "none" = bubble simply stays where the user drops it.
      positionGravity: PositionGravity.none,
      enableDrag: true,
      overlayTitle: 'Companion Hub',
      overlayContent: 'Daily checklist bubble is active',
    );
  }

  static Future<void> hide() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}
