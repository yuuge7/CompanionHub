import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/games.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../services/notification_service.dart';
import 'accounts_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _fmtMinutes(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minutesOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _accountsSummary(AppSettings settings) {
    final extras = settings.allAccounts.where((a) => !a.isMain).length;
    if (!settings.multiAccountEnabled) {
      return extras == 0
          ? 'Turn on multi-account mode first'
          : '$extras extra account${extras == 1 ? '' : 's'} paused';
    }
    return extras == 0
        ? 'Add a second account for any game'
        : '$extras extra account${extras == 1 ? '' : 's'}';
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    int currentMinutes,
    void Function(int minutes) apply,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: currentMinutes ~/ 60, minute: currentMinutes % 60),
    );
    if (picked != null) apply(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        // ---- Games ----
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: const Text('Games'),
                subtitle: Text(
                  'Hidden games disappear from every tab, the bubble and the '
                  'home widget, and fire no alerts. Data is kept.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              for (final g in GameId.values)
                SwitchListTile(
                  secondary:
                      CircleAvatar(radius: 5, backgroundColor: g.config.color),
                  title: Text(g.config.name),
                  value: !settings.isHidden(g),
                  onChanged: (visible) {
                    final hidden = {...settings.hiddenGames};
                    if (visible) {
                      hidden.remove(g);
                    } else {
                      if (settings.visibleGames.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('At least one game must stay visible.')),
                        );
                        return;
                      }
                      hidden.add(g);
                    }
                    notifier.update(settings.copyWith(hiddenGames: hidden));
                  },
                ),
            ],
          ),
        ),

        // ---- Multi-account ----
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.people_alt_outlined),
                title: const Text('Multi-account mode'),
                subtitle: const Text(
                    'Track several accounts per game, each with its own '
                    'energy, pity plan, dailies and weeklies'),
                value: settings.multiAccountEnabled,
                onChanged: (v) => notifier
                    .update(settings.copyWith(multiAccountEnabled: v)),
              ),
              ListTile(
                enabled: settings.multiAccountEnabled,
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Manage accounts'),
                subtitle: Text(_accountsSummary(settings)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AccountsScreen())),
              ),
            ],
          ),
        ),

        // ---- Notifications ----
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Notifications'),
                subtitle: const Text(
                    'Cap warnings, weekly burn warnings, summaries'),
                value: settings.notificationsEnabled,
                onChanged: (v) => notifier
                    .update(settings.copyWith(notificationsEnabled: v)),
              ),
              ListTile(
                enabled: settings.notificationsEnabled,
                leading: const Icon(Icons.notification_important_outlined),
                title: const Text('Request notification permissions'),
                subtitle: const Text(
                    'Grant notifications + exact alarms (Android 12+)'),
                onTap: () async {
                  final ok = await NotificationService.instance
                      .requestPermissions();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Notifications permitted.'
                            : 'Notifications denied — alerts will not fire.')));
                  }
                },
              ),
            ],
          ),
        ),

        // ---- Sleep Safe ----
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Sleep Safe'),
                subtitle: const Text(
                    'No alarms at night — a silent summary with the accrued '
                    'overflow arrives in the morning instead'),
                value: settings.sleepSafeEnabled,
                onChanged: (v) =>
                    notifier.update(settings.copyWith(sleepSafeEnabled: v)),
              ),
              ListTile(
                enabled: settings.sleepSafeEnabled,
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Sleep window starts'),
                trailing: Text(_fmtMinutes(settings.sleepStartMinutes),
                    style: theme.textTheme.titleMedium),
                onTap: () => _pickTime(
                  context,
                  ref,
                  settings.sleepStartMinutes,
                  (m) =>
                      notifier.update(settings.copyWith(sleepStartMinutes: m)),
                ),
              ),
              ListTile(
                enabled: settings.sleepSafeEnabled,
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Sleep window ends'),
                trailing: Text(_fmtMinutes(settings.sleepEndMinutes),
                    style: theme.textTheme.titleMedium),
                onTap: () => _pickTime(
                  context,
                  ref,
                  settings.sleepEndMinutes,
                  (m) =>
                      notifier.update(settings.copyWith(sleepEndMinutes: m)),
                ),
              ),
              ListTile(
                enabled: settings.sleepSafeEnabled,
                leading: const Icon(Icons.coffee_outlined),
                title: const Text('Morning summary at'),
                trailing: DropdownButton<int>(
                  value: settings.summaryHour,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var h = 5; h <= 11; h++)
                      DropdownMenuItem(
                          value: h,
                          child: Text('${h.toString().padLeft(2, '0')}:00')),
                  ],
                  onChanged: settings.sleepSafeEnabled
                      ? (h) => notifier
                          .update(settings.copyWith(summaryHour: h ?? 8))
                      : null,
                ),
              ),
            ],
          ),
        ),

        // ---- NTE burn warning ----
        Card(
          child: SwitchListTile(
            title: const Text('NTE burn warning'),
            subtitle: const Text(
                'Sunday-evening reminder when weekly limits are unfinished'),
            value: settings.burnWarningEnabled,
            onChanged: (v) =>
                notifier.update(settings.copyWith(burnWarningEnabled: v)),
          ),
        ),

        // ---- About ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gacha Companion Hub',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  '100% offline: all data lives on this device. Timers, '
                  'forecasts and alarms are computed locally — no account, '
                  'no network, no Firebase.\n\n'
                  'Resets follow each game\'s server clock and are shown in '
                  'your time zone, daylight saving included: '
                  '${[for (final g in GameId.values) '${g.config.shortName} ${g.config.reset.label}'].join(', ')}. '
                  'NTE weeklies reset Monday at the same time.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
