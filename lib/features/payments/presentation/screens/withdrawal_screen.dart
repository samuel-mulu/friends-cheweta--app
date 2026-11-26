import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';
import 'package:friends_game_app/features/payments/presentation/controllers/payment_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class WithdrawalScreen extends ConsumerStatefulWidget {
  const WithdrawalScreen({super.key});

  @override
  ConsumerState<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends ConsumerState<WithdrawalScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _destination = TextEditingController();
  final _password = TextEditingController();
  String _channel = 'TELEBIRR';

  @override
  void dispose() {
    _amount.dispose();
    _destination.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final sent =
        await ref.read(paymentControllerProvider.notifier).submitWithdrawal(
              amountMinor: paymentAmountMinor(_amount.text)!,
              channel: _channel,
              destination: _destination.text,
              password: _password.text,
            );
    if (!sent || !mounted) return;
    _password.clear();
    _amount.clear();
    _destination.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Withdrawal requested. The amount is reserved for review.')),
    );
    context.pushReplacement('/withdrawal-history');
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(paymentControllerProvider);
    final wallet = ref.watch(walletControllerProvider).wallet;
    final telebirr = _channel == 'TELEBIRR';

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw'), actions: [
        IconButton(
            tooltip: 'Withdrawal history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/withdrawal-history')),
      ]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Form(
            key: _form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wallet != null)
                    Text(
                        'Available ${MoneyFormatter.minorToEtb(wallet.availableBalance)}',
                        style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _channel,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: const [
                      DropdownMenuItem(
                          value: 'TELEBIRR', child: Text('Telebirr')),
                      DropdownMenuItem(value: 'CBE', child: Text('CBE')),
                    ],
                    onChanged: action.loading
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _channel = value;
                                _destination.clear();
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _amount,
                    label: 'Amount (ETB)',
                    readOnly: action.loading,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final minor = paymentAmountMinor(value);
                      if (minor == null) {
                        return 'Enter a positive amount with up to two decimals.';
                      }
                      if (wallet != null &&
                          BigInt.parse(minor) > wallet.availableBalance) {
                        return 'Insufficient available balance.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _destination,
                    label: telebirr
                        ? 'Telebirr phone number'
                        : 'CBE account number',
                    readOnly: action.loading,
                    keyboardType:
                        telebirr ? TextInputType.phone : TextInputType.number,
                    validator: telebirr
                        ? Validators.phone
                        : (value) =>
                            RegExp(r'^\d{6,32}$').hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter a valid CBE account number.',
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _password,
                    label: 'Confirm account password',
                    obscureText: true,
                    readOnly: action.loading,
                    prefixIcon: Icons.lock_outline_rounded,
                    validator: Validators.password,
                  ),
                  if (action.error != null) ...[
                    const SizedBox(height: 12),
                    Text(action.error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                      label: 'Request withdrawal',
                      loading: action.loading,
                      onPressed: _submit),
                ]),
          ),
        ),
      ),
    );
  }
}
