import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletControllerProvider);
    if (state.loading && state.wallet == null) return const Center(child: CircularProgressIndicator());
    if (state.wallet == null) return AppErrorView(message: state.error ?? 'Wallet unavailable.', onRetry: () => ref.read(walletControllerProvider.notifier).load());
    return RefreshIndicator(
      onRefresh: () => ref.read(walletControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          Text('Wallet activity', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Your balance and payment actions live in the sidebar.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () => context.push('/deposit-history'), child: const Text('Deposit history')),
              OutlinedButton(onPressed: () => context.push('/withdrawal-history'), child: const Text('Withdrawal history')),
            ],
          ),
          const SizedBox(height: 24),
          Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (state.transactions.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No transactions yet.')))
          else
            ...state.transactions.map((tx) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
                  title: Text(tx.type.replaceAll('_', ' ')),
                  subtitle: Text(tx.createdAt.toLocal().toString()),
                  trailing: Text(MoneyFormatter.minorToEtb(tx.amountMinor), style: const TextStyle(fontWeight: FontWeight.w600)),
                )),
        ],
      ),
    );
  }
}
