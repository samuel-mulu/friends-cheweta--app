import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/wallet/domain/wallet_transaction.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// The balance up top with the two money actions, then the activity.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletControllerProvider);
    if (state.loading && state.wallet == null) return const Center(child: CircularProgressIndicator());
    if (state.wallet == null) {
      return AppErrorView(message: state.error ?? 'Wallet unavailable.', onRetry: () => ref.read(walletControllerProvider.notifier).load());
    }
    final wallet = state.wallet!;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () => ref.read(walletControllerProvider.notifier).refresh(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              AppPanel(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Available balance', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(MoneyFormatter.minorToEtb(wallet.availableBalance), style: AppType.money(size: 40, color: palette.money)),
                  ),
                  if (wallet.lockedBalance > BigInt.zero) ...[
                    const SizedBox(height: 2),
                    Text('${MoneyFormatter.minorToEtb(wallet.lockedBalance)} in a match', style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: FilledButton(onPressed: () => context.push('/deposit'), child: const Text('Deposit'))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton(onPressed: () => context.push('/withdraw'), child: const Text('Withdraw'))),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _HistoryLink(icon: Icons.south_west_rounded, label: 'Deposits', onTap: () => context.push('/deposit-history')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HistoryLink(icon: Icons.north_east_rounded, label: 'Withdrawals', onTap: () => context.push('/withdrawal-history')),
                ),
              ]),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Recent activity'),
              if (state.transactions.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No activity yet',
                  message: 'Deposits, stakes, prizes and withdrawals show up here.',
                )
              else
                AppPanel(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final (index, tx) in state.transactions.indexed) ...[
                      if (index > 0) Divider(indent: 64, color: palette.surfaceAlt),
                      _TransactionRow(tx: tx),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryLink extends StatelessWidget {
  const _HistoryLink({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      radius: 14,
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
        Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
      ]),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx});
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final flow = tx.flow;
    final amount = MoneyFormatter.minorToEtb(tx.amountMinor.abs());
    final (icon, iconColor, amountText, amountColor) = switch (flow) {
      MoneyFlow.inflow => (Icons.south_west_rounded, AppColors.liveSoft, '+$amount', AppColors.liveSoft),
      MoneyFlow.outflow => (Icons.north_east_rounded, theme.colorScheme.onSurfaceVariant, '−$amount', theme.colorScheme.onSurface),
      MoneyFlow.neutral => (Icons.receipt_long_outlined, theme.colorScheme.onSurfaceVariant, amount, theme.colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: palette.surfaceAlt, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(DateFormat('d MMM, HH:mm').format(tx.createdAt.toLocal()), style: theme.textTheme.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        Text(amountText, style: AppType.money(size: 17, color: amountColor)),
      ]),
    );
  }
}
