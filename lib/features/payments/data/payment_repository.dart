import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';

class PaymentRepository {
  PaymentRepository(this._api);
  final ApiClient _api;

  Future<PaymentSubmission> submitDeposit({required String amountMinor, required String channel, required String transactionReference, required String idempotencyKey, String? note}) async {
    final response = await _api.request<Map<String, dynamic>>('/payments/deposits', method: 'POST', data: {
      'amountMinor': amountMinor,
      'channel': channel,
      'transactionReference': transactionReference.trim(),
      'idempotencyKey': idempotencyKey,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return PaymentSubmission.fromJson(response.data!);
  }

  Future<PaymentSubmission> submitWithdrawal({required String amountMinor, required String channel, required String destination, required String idempotencyKey}) async {
    final response = await _api.request<Map<String, dynamic>>('/payments/withdrawals', method: 'POST', data: {
      'amountMinor': amountMinor,
      'channel': channel,
      'destination': destination.trim(),
      'idempotencyKey': idempotencyKey,
    });
    return PaymentSubmission.fromJson(response.data!);
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => PaymentRepository(ref.watch(apiClientProvider)));
