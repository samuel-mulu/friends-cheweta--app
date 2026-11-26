import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/storage/json_cache.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/wallet/data/wallet_repository.dart';
import 'package:friends_game_app/features/wallet/domain/wallet.dart';
import 'package:friends_game_app/features/wallet/domain/wallet_transaction.dart';

class WalletViewState {
  const WalletViewState({this.wallet, this.transactions = const [], this.loading = false, this.refreshing = false, this.error});
  final Wallet? wallet;
  final List<WalletTransaction> transactions;
  final bool loading;
  final bool refreshing;
  final String? error;
}

class WalletController extends Notifier<WalletViewState> {
  int _loadVersion = 0;
  /// Per account, so a different sign-in never shows someone else's balance.
  String? get _cacheKey {
    final userId = ref.read(authControllerProvider).user?.id;
    return userId == null ? null : 'wallet.$userId';
  }

  @override
  WalletViewState build() {
    final userId = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    _loadVersion++;
    if (userId != null) Future.microtask(load);
    final key = _cacheKey;
    final raw = key == null ? null : ref.read(jsonCacheProvider).read(key);
    final cached = raw is Map ? Wallet.fromJson(Map<String, dynamic>.from(raw)) : null;
    return WalletViewState(wallet: cached, loading: cached == null, refreshing: cached != null);
  }

  Future<void> load() async {
    final key = _cacheKey;
    if (key == null) return;
    final version = ++_loadVersion;
    state = WalletViewState(wallet: state.wallet, transactions: state.transactions, loading: state.wallet == null, refreshing: state.wallet != null);
    try {
      final results = await Future.wait([
        ref.read(walletRepositoryProvider).getWallet(),
        ref.read(walletRepositoryProvider).getTransactions(),
      ]);
      if (version != _loadVersion || key != _cacheKey) return;
      final wallet = results[0] as Wallet;
      state = WalletViewState(wallet: wallet, transactions: results[1] as List<WalletTransaction>);
      await ref.read(jsonCacheProvider).write(key, wallet.toJson());
    } on AppFailure catch (failure) {
      if (version != _loadVersion || key != _cacheKey) return;
      state = WalletViewState(wallet: state.wallet, transactions: state.transactions, error: failure.message);
    }
  }

  Future<void> refresh() => load();
}

final walletControllerProvider = NotifierProvider<WalletController, WalletViewState>(WalletController.new);
