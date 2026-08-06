import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/energy_math.dart';
import '../core/games.dart';
import '../core/reset_time.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import 'nte_weekly_screen.dart';

/// Module A: Universal Energy & Overflow Timer.
class EnergyScreen extends ConsumerWidget {
  const EnergyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final states = ref.watch(energyProvider);
    final games = ref.watch(visibleGamesProvider);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final g in games)
          _EnergyCard(game: g, state: states[g]!, now: now),
      ],
    );
  }
}

class _EnergyCard extends ConsumerWidget {
  const _EnergyCard({required this.game, required this.state, required this.now});

  final GameId game;
  final EnergyState state;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = game.config;
    final snap = projectEnergy(cfg, state.energy, state.updatedAt, now);
    final theme = Theme.of(context);

    String capLine;
    if (snap.atAbsoluteCap) {
      capLine = cfg.hasOverflow
          ? 'Fully capped — overflow reserve is full!'
          : 'Capped — energy is being wasted!';
    } else if (snap.atNormalCap) {
      capLine =
          'At cap — overflow full ${_fmtEta(snap.absoluteCapAt!, now)}';
    } else {
      capLine = 'Full ${_fmtEta(snap.normalCapAt!, now)}';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openEditor(context, ref, snap.current),
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
                    child: Text(cfg.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (game == GameId.nte)
                    IconButton(
                      tooltip: 'NTE Weekly Dashboard',
                      icon: const Icon(Icons.event_repeat),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NteWeeklyScreen()),
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
                        .setNotify(game, !state.notifyCap),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${snap.normalPortion}',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(' / ${cfg.normalCap} ${cfg.energyName}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const Spacer(),
                  if (cfg.hasOverflow && snap.overflowPortion > 0)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: cfg.color.withValues(alpha: .4)),
                      backgroundColor: Colors.transparent,
                      label: Text('+${snap.overflowPortion} reserve',
                          style: TextStyle(color: cfg.color, fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: snap.normalFraction,
                  minHeight: 8,
                  color: cfg.color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              if (cfg.hasOverflow) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: snap.overflowFraction,
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

  void _openEditor(BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EnergyEditor(game: game, current: current),
    );
  }
}

class _EnergyEditor extends ConsumerStatefulWidget {
  const _EnergyEditor({required this.game, required this.current});

  final GameId game;
  final int current;

  @override
  ConsumerState<_EnergyEditor> createState() => _EnergyEditorState();
}

class _EnergyEditorState extends ConsumerState<_EnergyEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.current}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Some numeric keyboards emit grouping separators or minus signs;
    // strip everything but digits so the save can't silently no-op.
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final value = int.tryParse(digits);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a number first.')),
      );
      return;
    }
    await ref.read(energyProvider.notifier).setEnergy(widget.game, value);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.game.config;
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
          Text('Update ${cfg.energyName}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Enter the value shown in-game right now.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText:
                  '${cfg.energyName} (0–${cfg.absoluteCap})',
              suffixText: '/ ${cfg.normalCap}',
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
                    final v = int.tryParse(_controller.text) ?? 0;
                    _controller.text =
                        '${(v + delta).clamp(0, cfg.absoluteCap)}';
                  },
                ),
              ActionChip(
                label: const Text('0'),
                onPressed: () => _controller.text = '0',
              ),
              ActionChip(
                label: Text('Full (${cfg.normalCap})'),
                onPressed: () => _controller.text = '${cfg.normalCap}',
              ),
            ],
          ),
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
