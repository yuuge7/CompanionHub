import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/games.dart';
import '../core/reset_time.dart';
import '../data/models.dart';
import '../providers/providers.dart';

/// NTE Weekly Reset Dashboard: City Tycoon stamina, Anomaly Pilgrimage
/// limits, Realm of Greed, Monday reset countdown and burn-warning status —
/// all for one NTE [account].
class NteWeeklyScreen extends ConsumerWidget {
  const NteWeeklyScreen({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(nteWeeklyProvider);
    final notifier = ref.read(nteWeeklyProvider.notifier);
    final weekly = notifier.of(account);
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final theme = Theme.of(context);
    final cfg = GameId.nte.config;

    final nextReset =
        nextWeeklyReset(kNteWeeklyResetWeekday, cfg.reset, now);
    final maxStamina = nteCityStaminaForLevel(weekly.tycoonLevel);

    return Scaffold(
      appBar: AppBar(
        title: Text(settings.withAccountLabel(
            'NTE Weekly Dashboard', GameId.nte, account.id)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- Reset countdown ----
          Card(
            child: ListTile(
              leading: Icon(Icons.event_repeat, color: cfg.color),
              title: Text('Weekly reset: Monday ${cfg.reset.label} '
                  '(${DateFormat('EEE HH:mm').format(nextReset)} your time)'),
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
                        onPressed: () => notifier.setTycoonLevel(
                            account, weekly.tycoonLevel - 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => notifier.setTycoonLevel(
                            account, weekly.tycoonLevel + 1),
                      ),
                    ],
                  ),
                  Slider(
                    value: weekly.tycoonLevel.toDouble(),
                    min: 1,
                    max: kNteMaxTycoonLevel.toDouble(),
                    divisions: kNteMaxTycoonLevel - 1,
                    label: '${weekly.tycoonLevel}',
                    onChanged: (v) =>
                        notifier.setTycoonLevel(account, v.round()),
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
                    onChanged: (v) =>
                        notifier.toggleTask(account, i, v ?? false),
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
