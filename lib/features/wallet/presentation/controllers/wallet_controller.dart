import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
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
  @override
  WalletViewState build() {
    Future.microtask(load);
    return const WalletViewState(loading: true);
  }

  Future<void> load() async {
    state = WalletViewState(wallet: state.wallet, transactions: state.transactions, loading: state.wallet == null, refreshing: state.wallet != null);
    try {
      final results = await Future.wait([
        ref.read(walletRepositoryProvider).getWallet(),
        ref.read(walletRepositoryProvider).getTransactions(),
      ]);
      state = WalletViewState(wallet: results[0] as Wallet, transactions: results[1] as List<WalletTransaction>);
    } on AppFailure catch (failure) {
      state = WalletViewState(wallet: state.wallet, transactions: state.transactions, error: failure.message);
    }
  }

  Future<void> refresh() => load();
}

final walletControllerProvider = NotifierProvider<WalletController, WalletViewState>(WalletController.new);
