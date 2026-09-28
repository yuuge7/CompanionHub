import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/energy_math.dart';
import '../core/games.dart';
import '../core/reset_time.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import 'account_tag.dart';
import 'nte_weekly_screen.dart';

/// Module A: Universal Energy & Overflow Timer.
class EnergyScreen extends ConsumerWidget {
  const EnergyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    ref.watch(energyProvider); // rebuild when any anchor changes
    final energy = ref.read(energyProvider.notifier);
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final a in ref.watch(visibleAccountsProvider))
          _EnergyCard(
            account: a,
            showAccount: settings.showsAccountLabels(a.game),
            state: energy.of(a),
            now: now,
          ),
      ],
    );
  }
}

class _EnergyCard extends ConsumerWidget {
  const _EnergyCard({
    required this.account,
    required this.showAccount,
    required this.state,
    required this.now,
  });

  final Account account;
  final bool showAccount;
  final EnergyState state;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = account.game.config;
    final snap = state.projectAt(now);
    final theme = Theme.of(context);

    String capLine;
    if (snap.wasting) {
      capLine = cfg.hasReserve
          ? 'Fully capped — ${cfg.reserveName} is full!'
          : snap.overfilled
              ? 'Above cap — regeneration paused'
              : 'Capped — energy is being wasted!';
    } else if (snap.atCap) {
      capLine = '${snap.overfilled ? 'Above cap' : 'At cap'} — reserve full '
          '${_fmtEta(snap.reserveFullAt!, now)}';
    } else {
      capLine = 'Full ${_fmtEta(snap.capAt!, now)}';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openEditor(context, snap),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 5,
                    backgroundColor: cfg.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameAccountTitle(
                      account: account,
                      showAccount: showAccount,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (account.game == GameId.nte)
                    IconButton(
                      tooltip: 'NTE Weekly Dashboard',
                      icon: const Icon(Icons.event_repeat),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => NteWeeklyScreen(account: account)),
                      ),
                    ),
                  IconButton(
                    tooltip: state.notifyCap
                        ? 'Cap alert on'
                        : 'Cap alert off',
                    icon: Icon(
                      state.notifyCap
                          ? Icons.notifications_active
                          : Icons.notifications_off_outlined,
                      color: state.notifyCap
                          ? cfg.color
                          : theme.colorScheme.outline,
                    ),
                    onPressed: () => ref
                        .read(energyProvider.notifier)
                        .setNotify(account, !state.notifyCap),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${snap.current}',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(' / ${snap.cap} ${cfg.energyName}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const Spacer(),
                  if (cfg.hasReserve && snap.reserve > 0)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: cfg.color.withValues(alpha: .4)),
                      backgroundColor: Colors.transparent,
                      label: Text('+${snap.reserve} reserve',
                          style: TextStyle(color: cfg.color, fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: snap.fraction,
                  minHeight: 8,
                  color: cfg.color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              if (cfg.hasReserve) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: snap.reserveFraction,
                    minHeight: 3,
                    color: cfg.color.withValues(alpha: .45),
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(capLine,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                  Text('tap to update',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outlineVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtEta(DateTime at, DateTime now) {
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final time = sameDay
        ? DateFormat('HH:mm').format(at)
        : DateFormat('EEE HH:mm').format(at);
    return 'at $time (in ${formatDuration(at.difference(now))})';
  }

  void _openEditor(BuildContext context, EnergySnapshot snap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EnergyEditor(account: account, snapshot: snap),
    );
  }
}

class _EnergyEditor extends ConsumerStatefulWidget {
  const _EnergyEditor({required this.account, required this.snapshot});

  final Account account;

  /// Projection at the moment the editor opened; pre-fills the fields.
  final EnergySnapshot snapshot;

  @override
  ConsumerState<_EnergyEditor> createState() => _EnergyEditorState();
}

class _EnergyEditorState extends ConsumerState<_EnergyEditor> {
  late final TextEditingController _main;
  late final TextEditingController _reserve;
  late int _cap;

  @override
  void initState() {
    super.initState();
    _main = TextEditingController(text: '${widget.snapshot.current}');
    _reserve = TextEditingController(text: '${widget.snapshot.reserve}');
    _cap = widget.snapshot.cap;
  }

  @override
  void dispose() {
    _main.dispose();
    _reserve.dispose();
    super.dispose();
  }

  // Some numeric keyboards emit grouping separators or minus signs;
  // strip everything but digits so the save can't silently no-op.
  static int? _parse(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));

  Future<void> _save() async {
    final cfg = widget.account.game.config;
    final main = _parse(_main);
    final reserve = cfg.hasReserve ? _parse(_reserve) : null;
    if (main == null || (cfg.hasReserve && reserve == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a number first.')),
      );
      return;
    }
    await ref.read(energyProvider.notifier).setEnergy(
          widget.account,
          energy: main,
          reserve: reserve,
          cap: cfg.hasCapUpgrades ? _cap : null,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.account.game.config;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              ref.watch(settingsProvider).withAccountLabel(
                  'Update ${cfg.energyName}',
                  widget.account.game,
                  widget.account.id),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Enter the values shown in-game right now.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('energy-main'),
            controller: _main,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: cfg.energyName,
              suffixText: '/ $_cap',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final delta in cfg.quickDeltas)
                ActionChip(
                  label: Text('$delta'),
                  onPressed: () {
                    final v = _parse(_main) ?? 0;
                    _main.text = '${(v + delta).clamp(0, kEnergyInputLimit)}';
                  },
                ),
              ActionChip(
                label: const Text('0'),
                onPressed: () => _main.text = '0',
              ),
              ActionChip(
                label: Text('Full ($_cap)'),
                onPressed: () => _main.text = '$_cap',
              ),
            ],
          ),
          if (cfg.hasReserve) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('energy-reserve'),
              controller: _reserve,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: cfg.reserveName,
                suffixText: '/ ${cfg.reserveCap}',
              ),
            ),
          ],
          if (cfg.hasCapUpgrades) ...[
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: cfg.capUpgradeName,
                helperText: 'Raises the ${cfg.energyName} cap',
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _cap,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (var lvl = 0; lvl < cfg.capOptions.length; lvl++)
                      DropdownMenuItem(
                        value: cfg.capOptions[lvl],
                        child: Text(lvl == 0
                            ? 'Not placed (cap ${cfg.capOptions[lvl]})'
                            : 'Lv $lvl (cap ${cfg.capOptions[lvl]})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _cap = v ?? _cap),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
