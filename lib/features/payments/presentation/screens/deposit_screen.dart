import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/payments/presentation/controllers/payment_controller.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});
  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String _channel = 'CBE';

  @override
  void dispose() { _amount.dispose(); _reference.dispose(); _note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paymentControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Deposit')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add funds', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Submit your transfer details. Your wallet is credited only after approval.'),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(initialValue: _channel, decoration: const InputDecoration(labelText: 'Channel'), items: const [
            DropdownMenuItem(value: 'CBE', child: Text('CBE')),
            DropdownMenuItem(value: 'TELEBIRR', child: Text('telebirr')),
          ], onChanged: state.loading ? null : (v) => setState(() => _channel = v ?? 'CBE')),
          const SizedBox(height: 16),
          AppTextField(controller: _amount, label: 'Amount (ETB)', keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: Validators.positiveAmount),
          const SizedBox(height: 16),
          AppTextField(controller: _reference, label: 'Transaction reference', validator: (v) => Validators.required(v, label: 'Transaction reference')),
          const SizedBox(height: 16),
          AppTextField(controller: _note, label: 'Note (optional)'),
          if (state.error != null) ...[const SizedBox(height: 12), Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 24),
          AppButton(label: 'Submit deposit', loading: state.loading, onPressed: () async {
            if (!_key.currentState!.validate()) return;
            final ok = await ref.read(paymentControllerProvider.notifier).submitDeposit(
              amountMinor: MoneyFormatter.etbInputToMinor(_amount.text), channel: _channel, reference: _reference.text, note: _note.text,
            );
            if (ok && context.mounted) {
              await showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('Deposit submitted'), content: const Text('Your deposit is pending verification. Your wallet will update after approval.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]));
              if (context.mounted) context.pop();
            }
          }),
        ])),
      )),
    );
  }
}
