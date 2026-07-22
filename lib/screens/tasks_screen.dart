import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../providers/providers.dart';
import '../services/overlay_service.dart';

/// Module C: Multi-game daily task checklists + floating bubble controls.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen>
    with WidgetsBindingObserver {
  bool _overlayActive = false;
  bool _overlayPermitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshOverlayStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system "Display over other apps" screen.
    if (state == AppLifecycleState.resumed) _refreshOverlayStatus();
  }

  Future<void> _refreshOverlayStatus() async {
    try {
      final permitted = await OverlayService.isPermissionGranted();
      final active = await OverlayService.isActive();
      if (mounted) {
        setState(() {
          _overlayPermitted = permitted;
          _overlayActive = active;
        });
      }
    } catch (e) {
      debugPrint('Overlay status check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final tasks = ref.watch(tasksProvider.notifier);
    ref.watch(tasksProvider); // rebuild when checks change
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        // ---- Floating bubble control ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bubble_chart,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Floating checklist bubble',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Draws a draggable bubble over your game so you can tick '
                  'dailies without alt-tabbing. Needs the "Display over other '
                  'apps" permission.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (!_overlayPermitted)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Grant permission'),
                        onPressed: () async {
                          await OverlayService.requestPermission();
                          await _refreshOverlayStatus();
                        },
                      )
                    else if (!_overlayActive)
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Show bubble'),
                        onPressed: () async {
                          await OverlayService.show(
                              MediaQuery.of(context).devicePixelRatio);
                          await _refreshOverlayStatus();
                        },
                      )
                    else
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.stop),
                        label: const Text('Hide bubble'),
                        onPressed: () async {
                          await OverlayService.hide();
                          await _refreshOverlayStatus();
                        },
                      ),
                    const SizedBox(width: 12),
                    Icon(
                      _overlayActive ? Icons.circle : Icons.circle_outlined,
                      size: 12,
                      color: _overlayActive
                          ? Colors.greenAccent
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(_overlayActive ? 'active' : 'inactive',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ---- Per-game checklists ----
        for (final g in ref.watch(visibleGamesProvider))
          _GameTaskCard(game: g, now: now, tasks: tasks),
      ],
    );
  }
}

class _GameTaskCard extends ConsumerWidget {
  const _GameTaskCard({
    required this.game,
    required this.now,
    required this.tasks,
  });

  final GameId game;
  final DateTime now;
  final TasksNotifier tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = game.config;
    final theme = Theme.of(context);
    final total = cfg.dailyTasks.length;
    final done = [
      for (var i = 0; i < total; i++)
        if (tasks.isChecked(game, i, now)) i
    ].length;
    final resetIn =
        nextDailyReset(cfg.dailyResetHour, now).difference(now);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: done < total,
        leading: CircleAvatar(radius: 5, backgroundColor: cfg.color),
        title: Text(cfg.name,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$done/$total done • resets in ${formatDuration(resetIn)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        trailing: done == total
            ? const Icon(Icons.check_circle, color: Colors.greenAccent)
            : null,
        children: [
          for (var i = 0; i < total; i++)
            CheckboxListTile(
              dense: true,
              activeColor: cfg.color,
              controlAffinity: ListTileControlAffinity.leading,
              value: tasks.isChecked(game, i, now),
              title: Text(cfg.dailyTasks[i]),
              onChanged: (v) => tasks.toggle(game, i, v ?? false),
            ),
        ],
      ),
    );
  }
}
