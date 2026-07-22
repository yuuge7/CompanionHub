import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/store.dart';
import 'overlay/overlay_app.dart';
import 'screens/home_shell.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: CompanionHubApp()));
}

/// Entry point of the floating-bubble engine, spawned by
/// flutter_overlay_window's OverlayService. Must keep this exact name and the
/// vm:entry-point pragma or the overlay will show a blank window.
@pragma("vm:entry-point")
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const OverlayApp());
}

class CompanionHubApp extends StatelessWidget {
  const CompanionHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Companion Hub',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
