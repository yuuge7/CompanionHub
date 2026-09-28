import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../core/theme.dart';
import '../data/models.dart';
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
  Account _account = const Account(GameId.nte, Account.mainId);
  Timer? _ticker;

  /// True while Hive boxes are closed and reopened; builds must not read the
  /// store in that window.
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    // Reset countdown + auto-uncheck at server reset need periodic rebuilds.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_reloading) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _setExpanded(bool expanded) async {
    // Pick up hidden-game / account changes and task ticks the main app may
    // have written meanwhile (each engine holds its own Hive box cache).
    if (expanded) {
      _reloading = true;
      try {
        await Store.reloadSettings();
        await Store.reloadTasks();
      } finally {
        _reloading = false;
      }
    }
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

  bool _isChecked(Account a, int index, DateTime now) {
    final ms = Store.taskCheckedAtMs(a, index);
    if (ms == null) return false;
    return ms >=
        lastDailyReset(a.game.config.reset, now)
            .millisecondsSinceEpoch;
  }

  Future<void> _toggle(Account a, int index, bool checked) async {
    await Store.setTaskChecked(a, index, checked);
    // Tell the main engine (if alive) to reload its task state.
    await FlutterOverlayWindow.shareData('tasks_changed');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Skip hidden games / inactive accounts; fall back if the current one
    // vanished.
    final settings = Store.settings();
    final accounts = settings.visibleAccounts;
    if (accounts.isNotEmpty && !accounts.contains(_account)) {
      _account = accounts.first;
    }
    return Material(
      color: Colors.transparent,
      child: _expanded
          ? _buildChecklist(context, settings, accounts)
          : _buildBubble(context),
    );
  }

  // ---- Collapsed: small semi-transparent bubble ----
  Widget _buildBubble(BuildContext context) {
    final now = DateTime.now();
    final cfg = _account.game.config;
    final total = cfg.dailyTasks.length;
    final done = [
      for (var i = 0; i < total; i++)
        if (_isChecked(_account, i, now)) i
    ].length;

    return GestureDetector(
      onTap: () => _setExpanded(true),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xEE13141A),
          border: Border.all(color: cfg.color.withValues(alpha: .7)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist, color: cfg.color, size: 22),
            Text(
              '$done/$total',
              style: TextStyle(
                color: cfg.color,
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
  Widget _buildChecklist(
    BuildContext context,
    AppSettings settings,
    List<Account> accounts,
  ) {
    final now = DateTime.now();
    final cfg = _account.game.config;
    final resetIn = nextDailyReset(cfg.reset, now).difference(now);

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
                      for (final a in accounts)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                                settings.withAccountLabel(
                                    a.game.config.shortName, a.game, a.id),
                                style: const TextStyle(fontSize: 11)),
                            selected: _account == a,
                            selectedColor:
                                a.game.config.color.withValues(alpha: .25),
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _account = a),
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
                    value: _isChecked(_account, i, now),
                    title: Text(cfg.dailyTasks[i],
                        style: const TextStyle(fontSize: 13)),
                    onChanged: (v) => _toggle(_account, i, v ?? false),
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
