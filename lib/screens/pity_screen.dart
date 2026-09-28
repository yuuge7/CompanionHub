import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/games.dart';
import '../core/pity_math.dart';
import '../data/models.dart';
import '../providers/providers.dart';

/// Module B: Pity Forecaster. Projects currency income to a target date and
/// computes the exact probability of securing the featured character.
class PityScreen extends ConsumerStatefulWidget {
  const PityScreen({super.key});

  @override
  ConsumerState<PityScreen> createState() => _PityScreenState();
}

class _PityScreenState extends ConsumerState<PityScreen> {
  GameId _selected = GameId.hsr;

  /// Last account picked per game (multi-account mode).
  final Map<GameId, int> _accountIds = {};

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(visibleGamesProvider);
    if (games.isEmpty) {
      return const Center(child: Text('All games are hidden in Settings.'));
    }
    // Fall back when the selected game was hidden in Settings.
    final selected = games.contains(_selected) ? _selected : games.first;
    // ...and when the selected account was removed or the mode turned off.
    final accounts =
        ref.watch(settingsProvider).activeAccountsOf(selected);
    final account = accounts.firstWhere(
      (a) => a.id == _accountIds[selected],
      orElse: () => accounts.first,
    );
    ref.watch(pityPlansProvider);
    final plan = ref.read(pityPlansProvider.notifier).of(account);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<GameId>(
            segments: [
              for (final g in games)
                ButtonSegment(value: g, label: Text(g.config.shortName)),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _selected = s.first),
          ),
        ),
        if (accounts.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                for (final a in accounts)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(a.label),
                      selected: a == account,
                      selectedColor:
                          selected.config.color.withValues(alpha: .25),
                      onSelected: (_) =>
                          setState(() => _accountIds[selected] = a.id),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _PlanForm(key: ValueKey(account.key), plan: plan),
        _ForecastCard(plan: plan),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.widgets_outlined),
            label: const Text('Sync home screen widget'),
            onPressed: () async {
              await ref.read(pityPlansProvider.notifier).pushWidget();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Widget updated.')),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Input form for one game's plan. Recreated (via ValueKey) on game switch.
class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({super.key, required this.plan});

  final PityPlan plan;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  late final TextEditingController _pity;
  late final TextEditingController _currency;
  late final TextEditingController _ownedPulls;
  late final TextEditingController _daily;
  late final TextEditingController _weekly;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _pity = TextEditingController(text: '${p.pity}');
    _currency = TextEditingController(text: '${p.currency}');
    _ownedPulls = TextEditingController(text: '${p.ownedPulls}');
    _daily = TextEditingController(text: '${p.dailyIncome}');
    _weekly = TextEditingController(text: '${p.weeklyIncome}');
  }

  @override
  void dispose() {
    for (final c in [_pity, _currency, _ownedPulls, _daily, _weekly]) {
      c.dispose();
    }
    super.dispose();
  }

  PityPlan get _current =>
      ref.read(pityPlansProvider)[widget.plan.key] ?? widget.plan;

  void _commit() {
    final current = _current;
    final cfg = widget.plan.game.config;
    ref.read(pityPlansProvider.notifier).update(current.copyWith(
          pity: (int.tryParse(_pity.text) ?? 0).clamp(0, cfg.hardPity - 1),
          currency: int.tryParse(_currency.text) ?? 0,
          ownedPulls: int.tryParse(_ownedPulls.text) ?? 0,
          dailyIncome: int.tryParse(_daily.text) ?? 0,
          weeklyIncome: int.tryParse(_weekly.text) ?? 0,
        ));
  }

  Widget _numField(TextEditingController c, String label, {String? suffix}) =>
      Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          onChanged: (_) => _commit(),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cfg = widget.plan.game.config;
    ref.watch(pityPlansProvider);
    final plan = _current;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your account',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [
              _numField(_pity, 'Current pity', suffix: '/ ${cfg.hardPity}'),
              const SizedBox(width: 12),
              _numField(_currency, cfg.currencyName),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _numField(_ownedPulls, '${cfg.pullName} owned'),
              const SizedBox(width: 12),
              _numField(_daily, 'Daily income'),
              const SizedBox(width: 12),
              _numField(_weekly, 'Weekly income'),
            ]),
            if (cfg.has5050)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Guaranteed rate-up'),
                subtitle: const Text('Lost the last 50/50 coin flip'),
                value: plan.guaranteed,
                onChanged: (v) => ref
                    .read(pityPlansProvider.notifier)
                    .update(_current.copyWith(guaranteed: v)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(Icons.verified,
                        size: 16, color: cfg.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'No 50/50 in ${cfg.shortName}: every S-Rank is the '
                        'featured character.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ForecastCard extends ConsumerWidget {
  const _ForecastCard({required this.plan});

  final PityPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cfg = plan.game.config;
    final now = DateTime.now();
    final target = plan.targetDate;

    final projected =
        target == null ? plan.currency : plan.projectedCurrency(now, target);
    final pullsFromCurrency = projected ~/ cfg.pullCost;
    final totalPulls = plan.ownedPulls + pullsFromCurrency;
    final chance = chanceOfFeatured(cfg, plan.pity, plan.guaranteed, totalPulls);
    final worstCase = worstCasePulls(cfg, plan.pity, plan.guaranteed);
    final secured = totalPulls >= worstCase;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Forecast',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(target == null
                      ? 'Pick target date'
                      : DateFormat('d MMM yyyy').format(target)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          target ?? now.add(const Duration(days: 21)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      final cur =
                          ref.read(pityPlansProvider)[plan.key] ?? plan;
                      ref.read(pityPlansProvider.notifier).update(
                          cur.copyWith(
                              targetDateMs: picked.millisecondsSinceEpoch));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _row(theme, 'Days until target',
                target == null ? '—' : '${target.difference(now).inDays}'),
            _row(theme, 'Projected ${cfg.currencyName}', '$projected'),
            _row(theme, '÷ ${cfg.pullCost} per pull',
                '$pullsFromCurrency pulls'),
            _row(theme, '+ owned ${cfg.pullName}', '${plan.ownedPulls}'),
            const Divider(height: 20),
            _row(theme, 'Total pulls available', '$totalPulls', bold: true),
            _row(
                theme,
                'Worst case to secure',
                '$worstCase pulls'
                '${cfg.has5050 && !plan.guaranteed ? ' (lose 50/50)' : ''}'),
            const SizedBox(height: 12),
            Center(
              child: Column(
                children: [
                  Text(
                    '${(chance * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: secured
                          ? Colors.greenAccent
                          : Color.lerp(theme.colorScheme.error, cfg.color,
                              chance.clamp(0, 1)),
                    ),
                  ),
                  Text(
                    secured
                        ? 'Featured character 100% secured (hard pity covered)'
                        : 'chance to secure the featured character',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value,
      {bool bold = false}) {
    final style = bold
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}
