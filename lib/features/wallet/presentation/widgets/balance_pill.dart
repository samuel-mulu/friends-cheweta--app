import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// The player's available balance, always in reach. Tap opens the wallet.
class BalancePill extends ConsumerWidget {
  const BalancePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletControllerProvider
        .select((state) => state.wallet?.availableBalance));
    final palette = AppPalette.of(context);
    final text =
        balance == null ? '—' : MoneyFormatter.compactEtb(balance.toInt());
    final label =
        balance == null ? 'Open wallet' : 'Balance $text. Open wallet';
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compact =
        MediaQuery.sizeOf(context).width < 360 * textScale.clamp(1, 1.5);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: palette.moneyTint,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => context.go('/wallet'),
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minHeight: 44, minWidth: 44, maxWidth: 155),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet_rounded,
                          size: 17, color: palette.money),
                      if (!compact) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              text,
                              key: ValueKey(text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.money,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
