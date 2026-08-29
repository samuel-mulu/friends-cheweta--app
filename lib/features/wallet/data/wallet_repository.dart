import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/wallet/domain/wallet.dart';
import 'package:friends_game_app/features/wallet/domain/wallet_transaction.dart';

class WalletRepository {
  WalletRepository(this._api);
  final ApiClient _api;

  Future<Wallet> getWallet() async {
    final response = await _api.request<Map<String, dynamic>>('/wallet/me');
    return Wallet.fromJson(response.data!);
  }

  Future<List<WalletTransaction>> getTransactions({int limit = 30}) async {
    final response = await _api.request<dynamic>('/wallet/transactions/me', queryParameters: {'limit': limit});
    final data = response.data;
    final list = data is List ? data : (data is Map ? (data['items'] as List? ?? const []) : const []);
    return list.map((e) => WalletTransaction.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) => WalletRepository(ref.watch(apiClientProvider)));
