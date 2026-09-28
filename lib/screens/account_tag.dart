import 'package:flutter/material.dart';

import '../core/games.dart';
import '../data/models.dart';

/// Small outlined pill naming an account, tinted with its game's colour.
/// Shown next to a game's name only when that game tracks several accounts.
class AccountTag extends StatelessWidget {
  const AccountTag(this.account, {super.key});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final color = account.game.config.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(
        account.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Game name followed by an [AccountTag] when [showAccount] is set.
class GameAccountTitle extends StatelessWidget {
  const GameAccountTitle({
    super.key,
    required this.account,
    required this.showAccount,
    this.style,
  });

  final Account account;
  final bool showAccount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      account.game.config.name,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!showAccount) return name;
    return Row(
      children: [
        Flexible(child: name),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: AccountTag(account),
        ),
      ],
    );
  }
}
