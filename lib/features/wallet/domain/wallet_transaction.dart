/// Which way a wallet row moved the spendable balance.
enum MoneyFlow { inflow, outflow, neutral }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.createdAt,
    this.availableDelta,
  });

  final String id;
  final String type;
  final BigInt amountMinor;
  final DateTime createdAt;

  /// Change to the available (spendable) balance, from the server's ledger.
  /// Null on older payloads.
  final BigInt? availableDelta;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => WalletTransaction(
        id: json['id'].toString(),
        type: json['type']?.toString() ?? 'UNKNOWN',
        amountMinor: BigInt.parse(json['amount']?.toString() ?? json['amountMinor']?.toString() ?? '0'),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        availableDelta: BigInt.tryParse(json['availableDelta']?.toString() ?? ''),
      );

  /// A stake held then spent shows once as money out (the hold), and the spend
  /// itself as neutral, so the list never looks like it was charged twice.
  MoneyFlow get flow {
    final delta = availableDelta;
    if (delta != null) {
      if (delta > BigInt.zero) return MoneyFlow.inflow;
      if (delta < BigInt.zero) return MoneyFlow.outflow;
      return MoneyFlow.neutral;
    }
    return switch (type) {
      'DEPOSIT' || 'GAME_WIN' || 'GAME_ENTRY_RELEASE' || 'WITHDRAWAL_RELEASE' || 'REFUND' => MoneyFlow.inflow,
      'GAME_ENTRY_LOCK' || 'WITHDRAWAL_LOCK' || 'WITHDRAWAL' => MoneyFlow.outflow,
      _ => MoneyFlow.neutral,
    };
  }

  /// What a player reads in the activity list.
  String get label => switch (type) {
        'DEPOSIT' => 'Deposit',
        'WITHDRAWAL' => 'Withdrawal',
        'WITHDRAWAL_LOCK' => 'Withdrawal requested',
        'WITHDRAWAL_RELEASE' => 'Withdrawal returned',
        'WITHDRAWAL_PAYOUT' => 'Withdrawal paid out',
        'GAME_ENTRY_LOCK' => 'Match stake',
        'GAME_ENTRY_RELEASE' => 'Stake returned',
        'GAME_ENTRY_SPEND' => 'Stake played',
        'GAME_WIN' => 'Match win',
        'GAME_FEE' => 'Platform fee',
        'REFUND' => 'Refund',
        'ADMIN_ADJUSTMENT' => 'Adjustment',
        _ => _titleCase(type),
      };

  static String _titleCase(String raw) {
    final words = raw.toLowerCase().split('_').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'Transaction';
    return '${words.first[0].toUpperCase()}${words.first.substring(1)} ${words.skip(1).join(' ')}'.trim();
  }
}
