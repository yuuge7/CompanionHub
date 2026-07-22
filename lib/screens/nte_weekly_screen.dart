import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../providers/providers.dart';

/// NTE Weekly Reset Dashboard: City Tycoon stamina, weekly boss limits,
/// Realm of Greed, Monday-05:00 reset countdown and burn-warning status.
class NteWeeklyScreen extends ConsumerWidget {
  const NteWeeklyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(nteWeeklyProvider);
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final theme = Theme.of(context);
    final cfg = GameId.nte.config;

    final nextReset =
        nextWeeklyReset(kNteWeeklyResetWeekday, kNteWeeklyResetHour, now);
    final maxStamina = nteCityStaminaForLevel(weekly.tycoonLevel);

    return Scaffold(
      appBar: AppBar(title: const Text('NTE Weekly Dashboard')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- Reset countdown ----
          Card(
            child: ListTile(
              leading: Icon(Icons.event_repeat, color: cfg.color),
              title: const Text('Weekly reset: Monday 05:00'),
              subtitle: Text(
                  'Resets in ${formatDuration(nextReset.difference(now))}'),
            ),
          ),

          // ---- City Tycoon stamina ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('City Tycoon',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Tycoon level: ${weekly.tycoonLevel}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => ref
                            .read(nteWeeklyProvider.notifier)
                            .setTycoonLevel(weekly.tycoonLevel - 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => ref
                            .read(nteWeeklyProvider.notifier)
                            .setTycoonLevel(weekly.tycoonLevel + 1),
                      ),
                    ],
                  ),
                  Slider(
                    value: weekly.tycoonLevel.toDouble(),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    label: '${weekly.tycoonLevel}',
                    onChanged: (v) => ref
                        .read(nteWeeklyProvider.notifier)
                        .setTycoonLevel(v.round()),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('$maxStamina',
                            style: theme.textTheme.headlineMedium?.copyWith(
                                color: cfg.color,
                                fontWeight: FontWeight.w700)),
                        Text('max City Stamina this week',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---- Weekly checklist ----
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Weekly limits',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                for (var i = 0; i < kNteWeeklyTasks.length; i++)
                  CheckboxListTile(
                    value: weekly.done[i],
                    activeColor: cfg.color,
                    title: Text(kNteWeeklyTasks[i]),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => ref
                        .read(nteWeeklyProvider.notifier)
                        .toggleTask(i, v ?? false),
                  ),
              ],
            ),
          ),

          // ---- Burn warning status ----
          Card(
            child: ListTile(
              leading: Icon(
                weekly.allDone
                    ? Icons.check_circle
                    : Icons.local_fire_department,
                color: weekly.allDone ? Colors.greenAccent : Colors.orangeAccent,
              ),
              title: Text(weekly.allDone
                  ? 'All weekly limits cleared'
                  : '${weekly.remaining} weekly task(s) remaining'),
              subtitle: Text(
                !settings.notificationsEnabled || !settings.burnWarningEnabled
                    ? 'Burn warning disabled in Settings.'
                    : weekly.allDone
                        ? 'No burn warning scheduled.'
                        : 'Burn warning fires Sunday '
                            '${kNteBurnWarningHour.toString().padLeft(2, '0')}:00 '
                            'if anything is still unfinished.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
