import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_motion.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// The player's balance, always in reach: the amount opens the wallet, the
/// gold + adds funds.
class BalancePill extends ConsumerWidget {
  const BalancePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletControllerProvider.select((state) => state.wallet?.availableBalance));
    final palette = AppPalette.of(context);
    final text = balance == null ? '—' : MoneyFormatter.compactEtb(balance.toInt());
    final label = balance == null ? 'Open wallet' : 'Balance $text. Open wallet';
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compact = MediaQuery.sizeOf(context).width < 360 * textScale.clamp(1, 1.5);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      decoration: ShapeDecoration(
        color: scheme.surface,
        shape: StadiumBorder(side: BorderSide(color: palette.border)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => context.go('/wallet'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40, minWidth: 40, maxWidth: 128),
              child: Padding(
                padding: EdgeInsets.only(left: compact ? 10 : 12, right: 6),
                child: Center(
                  widthFactor: 1,
                  child: compact
                      ? Icon(Icons.account_balance_wallet_rounded, size: 18, color: palette.money)
                      : AnimatedSwitcher(
                          duration: AppMotion.state,
                          child: Text(
                            text,
                            key: ValueKey(text),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.money(size: 17, color: palette.money),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        // A 40 px target around the 30 px gold disc.
        Semantics(
          button: true,
          label: 'Add funds',
          excludeSemantics: true,
          child: Tooltip(
            message: 'Add funds',
            child: InkResponse(
              radius: 20,
              onTap: () => context.push('/deposit'),
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, size: 18, color: AppColors.onGold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
