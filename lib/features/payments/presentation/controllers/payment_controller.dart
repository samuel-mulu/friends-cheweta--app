import 'dart:async';

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

class PaymentController extends AutoDisposeNotifier<PaymentActionState> {
  final _uuid = const Uuid();
  ({String payload, String key})? _depositKey;
  ({String payload, String key})? _withdrawalKey;
  bool _disposed = false;

  @override
  PaymentActionState build() {
    ref.onDispose(() => _disposed = true);
    return const PaymentActionState();
  }

  Future<bool> submitDeposit(
          {required String amountMinor,
          required String channel,
          required String reference,
          String? note}) =>
      _run((repository) async {
        final payload =
            [channel, amountMinor, reference.trim().toUpperCase()].join('|');
        if (_depositKey?.payload != payload) {
          if (!await repository.referenceAvailable(channel, reference)) {
            throw const AppFailure(
                kind: FailureKind.business,
                message: 'This transaction reference is already in use.');
          }
          _depositKey = (payload: payload, key: _uuid.v4());
        }
        final result = await repository.submitDeposit(
          amountMinor: amountMinor,
          channel: channel,
          transactionReference: reference,
          idempotencyKey: _depositKey!.key,
          note: note,
        );
        _depositKey = null;
        return result;
      });

  Future<bool> submitWithdrawal(
          {required String amountMinor,
          required String channel,
          required String destination,
          required String password}) =>
      _run((repository) async {
        final payload = [channel, amountMinor, destination.trim()].join('|');
        if (_withdrawalKey?.payload != payload) {
          _withdrawalKey = (payload: payload, key: _uuid.v4());
        }
        final result = await repository.submitWithdrawal(
          amountMinor: amountMinor,
          channel: channel,
          destination: destination,
          password: password,
          idempotencyKey: _withdrawalKey!.key,
        );
        _withdrawalKey = null;
        return result;
      });

  Future<bool> updateAttempt(String id, {required bool cancel}) =>
      _run((repository) => repository.updateAttempt(id, cancel: cancel));

  Future<bool> _run(
      Future<PaymentSubmission> Function(PaymentRepository) operation) async {
    if (state.loading) return false;
    final previous = state.submission;
    state = PaymentActionState(loading: true, submission: previous);
    try {
      final result = await operation(ref.read(paymentRepositoryProvider));
      if (_disposed) return false;
      state = PaymentActionState(submission: result);
      ref.invalidate(depositHistoryProvider);
      ref.invalidate(withdrawalHistoryProvider);
      ref.invalidate(activeDepositAttemptsProvider);
      unawaited(ref.read(walletControllerProvider.notifier).refresh());
      return true;
    } on AppFailure catch (failure) {
      if (!_disposed) {
        state =
            PaymentActionState(submission: previous, error: failure.message);
      }
      return false;
    }
  }
}

final paymentControllerProvider =
    NotifierProvider.autoDispose<PaymentController, PaymentActionState>(
        PaymentController.new);
