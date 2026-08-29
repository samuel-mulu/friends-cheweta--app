import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/features/payments/data/payment_repository.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';
import 'package:uuid/uuid.dart';

class PaymentActionState {
  const PaymentActionState({this.loading = false, this.submission, this.error});
  final bool loading;
  final PaymentSubmission? submission;
  final String? error;
}

class PaymentController extends Notifier<PaymentActionState> {
  final _uuid = const Uuid();

  @override
  PaymentActionState build() => const PaymentActionState();

  Future<bool> submitDeposit({required String amountMinor, required String channel, required String reference, String? note}) async {
    if (state.loading) return false;
    state = const PaymentActionState(loading: true);
    try {
      final submission = await ref.read(paymentRepositoryProvider).submitDeposit(
        amountMinor: amountMinor,
        channel: channel,
        transactionReference: reference,
        idempotencyKey: 'flutter-deposit-${_uuid.v4()}',
        note: note,
      );
      state = PaymentActionState(submission: submission);
      await ref.read(walletControllerProvider.notifier).refresh();
      return true;
    } on AppFailure catch (failure) {
      state = PaymentActionState(error: failure.message);
      return false;
    }
  }

  Future<bool> submitWithdrawal({required String amountMinor, required String channel, required String destination}) async {
    if (state.loading) return false;
    state = const PaymentActionState(loading: true);
    try {
      final submission = await ref.read(paymentRepositoryProvider).submitWithdrawal(
        amountMinor: amountMinor,
        channel: channel,
        destination: destination,
        idempotencyKey: 'flutter-withdrawal-${_uuid.v4()}',
      );
      state = PaymentActionState(submission: submission);
      await ref.read(walletControllerProvider.notifier).refresh();
      return true;
    } on AppFailure catch (failure) {
      state = PaymentActionState(error: failure.message);
      return false;
    }
  }

  void reset() => state = const PaymentActionState();
}

final paymentControllerProvider = NotifierProvider<PaymentController, PaymentActionState>(PaymentController.new);
