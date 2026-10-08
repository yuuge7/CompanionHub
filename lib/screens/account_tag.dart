import 'package:flutter/material.dart';

import '../core/games.dart';
import '../data/models.dart';

/// Small outlined pill naming an account, tinted with its game's colour.
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

/// Game name followed by the account's [AccountTag]. Every account is tagged,
/// a game's only one included.
class GameAccountTitle extends StatelessWidget {
  const GameAccountTitle({super.key, required this.account, this.style});

  final Account account;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            account.game.config.name,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: AccountTag(account),
        ),
      ],
    );
  }
}
