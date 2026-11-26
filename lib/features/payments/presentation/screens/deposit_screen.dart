import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/utils/validators.dart';
import 'package:friends_game_app/core/widgets/app_button.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/core/widgets/app_text_field.dart';
import 'package:friends_game_app/features/payments/data/payment_repository.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';
import 'package:friends_game_app/features/payments/presentation/controllers/payment_controller.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String? _selectedChannel;
  String? _preview;
  bool _previewing = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _previewReceipt(String channel) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _previewing = true;
      _preview = null;
    });
    try {
      final preview = await ref
          .read(paymentRepositoryProvider)
          .preview(channel, _reference.text, paymentAmountMinor(_amount.text)!);
      if (mounted) setState(() => _preview = preview);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _preview = failure.message);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _submit(String channel) async {
    if (!_form.currentState!.validate()) return;
    final sent =
        await ref.read(paymentControllerProvider.notifier).submitDeposit(
              amountMinor: paymentAmountMinor(_amount.text)!,
              channel: channel,
              reference: _reference.text,
              note: _note.text,
            );
    if (!sent || !mounted) return;
    _amount.clear();
    _reference.clear();
    _note.clear();
    setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(depositConfigProvider);
    final attempts = ref.watch(activeDepositAttemptsProvider);
    final state = ref.watch(paymentControllerProvider);
    final latest = state.submission;
    final pending = {
      for (final attempt in attempts.valueOrNull ?? <PaymentSubmission>[])
        if (attempt.canCheck) attempt.id: attempt,
      if (latest != null && latest.canCheck) latest.id: latest,
    };
    if (latest != null && !latest.canCheck) pending.remove(latest.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Deposit'), actions: [
        IconButton(
            tooltip: 'Deposit history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/deposit-history')),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          children: [
            if (attempts.hasError)
              TextButton(
                  onPressed: () =>
                      ref.invalidate(activeDepositAttemptsProvider),
                  child: const Text('Reload pending verification')),
            for (final attempt in pending.values)
              _attemptCard(attempt, state.loading),
            if (latest != null && !latest.canCheck)
              Card(
                  child: ListTile(
                title: Text(latest.statusLabel(withdrawal: false)),
                subtitle: Text(latest.verificationCode != null
                    ? depositIssueLabel(latest.verificationCode)
                    : latest.status == PaymentStatus.approved
                        ? 'Your wallet has been credited.'
                        : 'See deposit history for details.'),
              )),
            if (state.error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(state.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            providers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => AppErrorView(
                  message: 'Deposit providers are unavailable.',
                  onRetry: () => ref.invalidate(depositConfigProvider)),
              data: (available) {
                if (available.isEmpty) {
                  return const Text('Deposits are temporarily unavailable.');
                }
                final provider = available.firstWhere(
                    (item) => item.channel == _selectedChannel,
                    orElse: () => available.first);
                return _providerForm(provider, available, state.loading);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerForm(
      DepositProvider provider, List<DepositProvider> available, bool loading) {
    final busy = loading || _previewing;
    final hasAccount = provider.account.isNotEmpty;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(provider.channel),
          initialValue: provider.channel,
          decoration: const InputDecoration(labelText: 'Provider'),
          items: available
              .map((option) => DropdownMenuItem(
                  value: option.channel,
                  child: Text(paymentChannelLabel(option.channel))))
              .toList(),
          onChanged: busy
              ? null
              : (value) => setState(() {
                    _selectedChannel = value;
                    _preview = null;
                  }),
        ),
        const SizedBox(height: 12),
        if (hasAccount)
          Card(
              child: ListTile(
            title: Text(provider.receiver.isEmpty
                ? 'Settlement account'
                : provider.receiver),
            subtitle: Text(
                'Transfer to ${provider.account}, then enter your receipt reference.'),
            trailing: IconButton(
              tooltip: 'Copy account',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: provider.account));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Account copied.')));
                }
              },
            ),
          ))
        else
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  'Settlement instructions are unavailable for this provider.')),
        const SizedBox(height: 12),
        AppTextField(
            onChanged: (_) => _clearPreview(),
            controller: _amount,
            label: 'Amount (ETB)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: busy,
            validator: (value) => paymentAmountMinor(value) == null
                ? 'Enter a positive amount with up to two decimals.'
                : null),
        const SizedBox(height: 16),
        AppTextField(
            onChanged: (_) => _clearPreview(),
            controller: _reference,
            label: 'Receipt reference',
            hint: provider.channel == 'CBE'
                ? 'Reference or CBE receipt link'
                : null,
            readOnly: busy,
            validator: (value) =>
                Validators.required(value, label: 'Receipt reference')),
        if (provider.approvalMode == 'MANUAL') ...[
          const SizedBox(height: 16),
          AppTextField(
              controller: _note, label: 'Note (optional)', readOnly: busy),
        ],
        if (provider.approvalMode == 'LOCAL')
          TextButton(
            onPressed: busy || !hasAccount
                ? null
                : () => _previewReceipt(provider.channel),
            child: Text(_previewing ? 'Checking receipt…' : 'Preview receipt'),
          ),
        if (_preview != null) Text(_preview!),
        const SizedBox(height: 24),
        AppButton(
            label: 'Submit deposit',
            loading: loading,
            onPressed:
                busy || !hasAccount ? null : () => _submit(provider.channel)),
      ]),
    );
  }

  Widget _attemptCard(PaymentSubmission attempt, bool busy) {
    final controller = ref.read(paymentControllerProvider.notifier);
    final amount = BigInt.tryParse(attempt.amountMinor ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${paymentChannelLabel(attempt.channel ?? '')} verification',
              style: Theme.of(context).textTheme.titleMedium),
          if (amount != null) Text(MoneyFormatter.minorToEtb(amount)),
          if (attempt.reference != null) Text(attempt.reference!),
          Text(depositIssueLabel(attempt.verificationCode)),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: busy
                    ? null
                    : () => controller.updateAttempt(attempt.id, cancel: false),
                child: const Text('Check again')),
            TextButton(
                onPressed: busy ? null : () => _cancelAttempt(attempt.id),
                child: const Text('Cancel verification')),
          ]),
        ]),
      ),
    );
  }

  void _clearPreview() {
    if (_preview != null) setState(() => _preview = null);
  }

  Future<void> _cancelAttempt(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel verification?'),
        content:
            const Text('You can submit the receipt again after cancellation.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep checking')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cancel verification')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(paymentControllerProvider.notifier)
          .updateAttempt(id, cancel: true);
    }
  }
}
