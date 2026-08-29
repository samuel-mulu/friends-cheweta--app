import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/payments/presentation/controllers/payment_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class WithdrawalScreen extends ConsumerStatefulWidget {
  const WithdrawalScreen({super.key});
  @override
  ConsumerState<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends ConsumerState<WithdrawalScreen> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _destination = TextEditingController();
  String _channel = 'TELEBIRR';

  @override
  void dispose() { _amount.dispose(); _destination.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentControllerProvider);
    final wallet = ref.watch(walletControllerProvider).wallet;
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Withdraw funds', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(wallet == null ? 'Available balance unavailable' : 'Available ${MoneyFormatter.minorToEtb(wallet.availableBalance)}'),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(initialValue: _channel, decoration: const InputDecoration(labelText: 'Channel'), items: const [
            DropdownMenuItem(value: 'TELEBIRR', child: Text('telebirr')),
            DropdownMenuItem(value: 'CBE', child: Text('CBE')),
          ], onChanged: state.loading ? null : (v) => setState(() => _channel = v ?? 'TELEBIRR')),
          const SizedBox(height: 16),
          AppTextField(controller: _amount, label: 'Amount (ETB)', keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) {
            final error = Validators.positiveAmount(v);
            if (error != null) return error;
            if (wallet != null) {
              final requested = BigInt.parse(MoneyFormatter.etbInputToMinor(v!));
              if (requested > wallet.availableBalance) return 'Insufficient available balance.';
            }
            return null;
          }),
          const SizedBox(height: 16),
          AppTextField(controller: _destination, label: 'Destination', keyboardType: TextInputType.phone, validator: (v) => Validators.required(v, label: 'Destination')),
          if (state.error != null) ...[const SizedBox(height: 12), Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 24),
          AppButton(label: 'Request withdrawal', loading: state.loading, onPressed: () async {
            if (!_key.currentState!.validate()) return;
            final ok = await ref.read(paymentControllerProvider.notifier).submitWithdrawal(
              amountMinor: MoneyFormatter.etbInputToMinor(_amount.text), channel: _channel, destination: _destination.text,
            );
            if (ok && context.mounted) {
              await showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('Withdrawal requested'), content: const Text('The amount is now reserved while your withdrawal is reviewed.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]));
              if (context.mounted) context.pop();
            }
          }),
        ])),
      )),
    );
  }
}
