import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/games.dart';
import '../data/models.dart';
import '../providers/providers.dart';

/// Name each game's account and, in multi-account mode, add and remove extra
/// accounts and pick which one the home screen widget shows.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              settings.multiAccountEnabled
                  ? 'Each account keeps its own energy, pity plan, dailies '
                      'and NTE weeklies. Tap an account to rename it; the '
                      'widget icon picks which account the home screen widget '
                      'shows.'
                  : 'Tap an account to name it; the name is shown on its '
                      'cards. Turn on multi-account mode in Settings to track '
                      'more than one account per game.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          for (final g in settings.visibleGames)
            _GameAccountsCard(game: g, settings: settings),
        ],
      ),
    );
  }
}

class _GameAccountsCard extends ConsumerWidget {
  const _GameAccountsCard({required this.game, required this.settings});

  final GameId game;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = game.config;
    final theme = Theme.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    // Only the main account while multi-account mode is off: extras are
    // paused and come back with the mode.
    final accounts = settings.activeAccountsOf(game);
    final widgetAccount = settings.widgetAccountOf(game);
    final canAdd = accounts.length < kMaxAccountsPerGame;

    return Card(
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  CircleAvatar(radius: 5, backgroundColor: cfg.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cfg.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (settings.multiAccountEnabled)
                    TextButton.icon(
                      icon:
                          const Icon(Icons.person_add_alt_1_outlined, size: 18),
                      label: const Text('Add account'),
                      onPressed: canAdd
                          ? () async {
                              final name = await _askName(
                                context,
                                title: 'Add ${cfg.shortName} account',
                                action: 'Add',
                              );
                              if (name != null) {
                                await notifier.addAccount(game, name);
                              }
                            }
                          : null,
                    )
                  else
                    const SizedBox(height: 36),
                ],
              ),
            ),
            for (final a in accounts)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 8),
                title: Text(a.label),
                subtitle: a.isMain ? const Text('Main account') : null,
                onTap: () async {
                  final name = await _askName(
                    context,
                    title: 'Rename account',
                    action: 'Save',
                    initial: a.name,
                  );
                  if (name != null) await notifier.renameAccount(a, name);
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (accounts.length > 1)
                      IconButton(
                        tooltip: a == widgetAccount
                            ? 'Shown on home widget'
                            : 'Show on home widget',
                        icon: Icon(
                          a == widgetAccount
                              ? Icons.widgets
                              : Icons.widgets_outlined,
                          color: a == widgetAccount
                              ? cfg.color
                              : theme.colorScheme.outline,
                        ),
                        onPressed: () => notifier.setWidgetAccount(a),
                      ),
                    if (!a.isMain)
                      IconButton(
                        tooltip: 'Remove account',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await _confirmRemove(context, a)) {
                            await notifier.removeAccount(a);
                          }
                        },
                      ),
                  ],
                ),
              ),
            if (!canAdd)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Up to $kMaxAccountsPerGame accounts per game.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Returns the entered name (possibly empty = default label), or null when
  /// the dialog was dismissed.
  static Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String action,
    String initial = '',
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) =>
            _NameDialog(title: title, action: action, initial: initial),
      );

  static Future<bool> _confirmRemove(BuildContext context, Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${a.label}?'),
        content: const Text(
          'Its energy, pity plan, dailies and weeklies are deleted. '
          'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Owns its controller so it is disposed only after the dialog's exit
/// animation, not while the field is still on screen.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Account name',
          hintText: 'e.g. Alt, EU server',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
