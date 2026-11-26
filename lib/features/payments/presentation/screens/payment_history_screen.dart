import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/payments/data/payment_repository.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';

class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key, required this.withdrawal});

  final bool withdrawal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        withdrawal ? withdrawalHistoryProvider : depositHistoryProvider;
    final title = withdrawal ? 'Withdrawal history' : 'Deposit history';
    final history = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => AppErrorView(
              message: 'Could not load payment history.',
              onRetry: () => ref.invalidate(provider)),
          data: (items) => RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                if (items.isEmpty)
                  Center(
                      child: Text(withdrawal
                          ? 'No withdrawals yet.'
                          : 'No deposits yet.')),
                for (final item in items) _tile(context, item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, PaymentSubmission item) {
    final amount = BigInt.tryParse(item.amountMinor ?? '');
    final date = item.createdAt?.toLocal();
    final detail = item.rejectionReason ??
        (item.verificationCode == null
            ? null
            : depositIssueLabel(item.verificationCode));
    final subtitle = [
      item.statusLabel(withdrawal: withdrawal),
      if (date != null) DateFormat.yMMMd().add_jm().format(date),
      if (item.reference != null) item.reference!,
      if (detail != null) detail,
    ].join('\n');
    return Card(
      child: ListTile(
        leading: Icon(
            withdrawal ? Icons.south_west_rounded : Icons.add_card_rounded),
        title: Text(paymentChannelLabel(item.channel ?? 'Payment')),
        subtitle: Text(subtitle),
        trailing:
            amount == null ? null : Text(MoneyFormatter.minorToEtb(amount)),
        onTap: item.canCheck ? () => context.push('/deposit') : null,
      ),
    );
  }
}
