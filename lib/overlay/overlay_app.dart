import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../services/overlay_service.dart';

/// Root widget of the SECOND FlutterEngine that lives inside the Android
/// overlay window (see overlayMain in main.dart). It reads/writes the same
/// Hive boxes as the app and pings the main engine via shareData so the app
/// refreshes instantly.
class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      color: Colors.transparent,
      home: const _OverlayBubble(),
    );
  }
}

class _OverlayBubble extends StatefulWidget {
  const _OverlayBubble();

  @override
  State<_OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<_OverlayBubble> {
  bool _expanded = false;
  GameId _game = GameId.nte;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Reset countdown + auto-uncheck at server reset need periodic rebuilds.
    _ticker = Timer.periodic(
        const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _setExpanded(bool expanded) async {
    // Pick up hidden-game changes the main app may have written meanwhile
    // (each engine holds its own Hive box cache).
    if (expanded) await Store.reloadSettings();
    // NOTE: unlike showOverlay (raw pixels), the plugin's resizeOverlay
    // applies its own dp->px conversion, so pass logical dp values here.
    // Multiplying by devicePixelRatio double-scales: a 300dp panel becomes
    // wider than the screen and the collapsed bubble ~3x too big.
    if (expanded) {
      await FlutterOverlayWindow.resizeOverlay(
        OverlayService.expandedWidthDp.round(),
        OverlayService.expandedHeightDp.round(),
        true,
      );
    } else {
      await FlutterOverlayWindow.resizeOverlay(
        OverlayService.collapsedDp.round(),
        OverlayService.collapsedDp.round(),
        true,
      );
    }
    if (mounted) setState(() => _expanded = expanded);
  }

  bool _isChecked(GameId g, int index, DateTime now) {
    final ms = Store.taskCheckedAtMs(g, index);
    if (ms == null) return false;
    return ms >=
        lastDailyReset(g.config.dailyResetHour, now).millisecondsSinceEpoch;
  }

  Future<void> _toggle(GameId g, int index, bool checked) async {
    await Store.setTaskChecked(g, index, checked);
    // Tell the main engine (if alive) to reload its task state.
    await FlutterOverlayWindow.shareData('tasks_changed');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Skip games hidden in Settings; fall back if the current one vanished.
    final games = Store.settings().visibleGames;
    if (games.isNotEmpty && !games.contains(_game)) _game = games.first;
    return Material(
      color: Colors.transparent,
      child: _expanded ? _buildChecklist(context, games) : _buildBubble(context),
    );
  }

  // ---- Collapsed: small semi-transparent bubble ----
  Widget _buildBubble(BuildContext context) {
    final now = DateTime.now();
    final total = _game.config.dailyTasks.length;
    final done = [
      for (var i = 0; i < total; i++)
        if (_isChecked(_game, i, now)) i
    ].length;

    return GestureDetector(
      onTap: () => _setExpanded(true),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xEE13141A),
          border: Border.all(color: _game.config.color.withValues(alpha: .7)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist, color: _game.config.color, size: 22),
            Text(
              '$done/$total',
              style: TextStyle(
                color: _game.config.color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Expanded: quick daily checklist ----
  Widget _buildChecklist(BuildContext context, List<GameId> games) {
    final now = DateTime.now();
    final cfg = _game.config;
    final resetIn = nextDailyReset(cfg.dailyResetHour, now).difference(now);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF213141A), // semi-transparent deep dark
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cfg.color.withValues(alpha: .5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final g in games)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(g.config.shortName,
                                style: const TextStyle(fontSize: 11)),
                            selected: _game == g,
                            selectedColor:
                                g.config.color.withValues(alpha: .25),
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _game = g),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_fullscreen, size: 18),
                onPressed: () => _setExpanded(false),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < cfg.dailyTasks.length; i++)
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: cfg.color,
                    value: _isChecked(_game, i, now),
                    title: Text(cfg.dailyTasks[i],
                        style: const TextStyle(fontSize: 13)),
                    onChanged: (v) => _toggle(_game, i, v ?? false),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.schedule, size: 12, color: Colors.white38),
              const SizedBox(width: 4),
              Text(
                'resets in ${formatDuration(resetIn)}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
