import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';

class PaymentRepository {
  PaymentRepository(this._api);
  final ApiClient _api;

  Future<List<DepositProvider>> depositConfig() async {
    final response =
        await _api.request<List<dynamic>>('/payments/deposits/config');
    return (response.data ?? [])
        .map((item) =>
            DepositProvider.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<bool> referenceAvailable(String channel, String reference) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/payments/deposits/check-ref',
        method: 'POST',
        data: {'channel': channel, 'transactionReference': reference.trim()});
    return response.data?['available'] == true;
  }

  Future<String> preview(
      String channel, String reference, String amountMinor) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/payments/deposits/preview',
        method: 'POST',
        data: {
          'channel': channel,
          'transactionReference': reference.trim(),
          'amountMinor': amountMinor
        });
    if (response.data?['available'] == true) {
      return 'Receipt amount and recipient match.';
    }
    return depositIssueLabel(
        response.data?['code']?.toString() ?? 'VERIFICATION_UNAVAILABLE');
  }

  Future<PaymentSubmission> submitDeposit(
      {required String amountMinor,
      required String channel,
      required String transactionReference,
      required String idempotencyKey,
      String? note}) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/payments/deposits',
        method: 'POST',
        data: {
          'amountMinor': amountMinor,
          'channel': channel,
          'transactionReference': transactionReference.trim(),
          'idempotencyKey': idempotencyKey,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        });
    return PaymentSubmission.fromJson(response.data!);
  }

  Future<PaymentSubmission> submitWithdrawal(
      {required String amountMinor,
      required String channel,
      required String destination,
      required String password,
      required String idempotencyKey}) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/payments/withdrawals',
        method: 'POST',
        data: {
          'amountMinor': amountMinor,
          'channel': channel,
          'destination': destination.trim(),
          'password': password,
          'idempotencyKey': idempotencyKey,
        });
    return PaymentSubmission.fromJson(response.data!);
  }

  Future<List<PaymentSubmission>> deposits() =>
      _history('/payments/deposits/me');
  Future<List<PaymentSubmission>> withdrawals() =>
      _history('/payments/withdrawals/me');
  Future<List<PaymentSubmission>> activeAttempts() =>
      _history('/payments/deposits/verification-attempts/active');

  Future<PaymentSubmission> updateAttempt(String id,
      {required bool cancel}) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/payments/deposits/verification-attempts/$id/${cancel ? 'cancel' : 'check'}',
        method: 'POST');
    return PaymentSubmission.fromJson(response.data!);
  }

  Future<List<PaymentSubmission>> _history(String path) async {
    final response = await _api.request<List<dynamic>>(path);
    return (response.data ?? [])
        .map((item) =>
            PaymentSubmission.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>(
    (ref) => PaymentRepository(ref.watch(apiClientProvider)));
final depositConfigProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(paymentRepositoryProvider).depositConfig());
final depositHistoryProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(paymentRepositoryProvider).deposits());
final withdrawalHistoryProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(paymentRepositoryProvider).withdrawals());
final activeDepositAttemptsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(paymentRepositoryProvider).activeAttempts());
