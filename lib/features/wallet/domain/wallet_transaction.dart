class WalletTransaction {
  const WalletTransaction({required this.id, required this.type, required this.amountMinor, required this.createdAt});

  final String id;
  final String type;
  final BigInt amountMinor;
  final DateTime createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => WalletTransaction(
        id: json['id'].toString(),
        type: json['type']?.toString() ?? 'UNKNOWN',
        amountMinor: BigInt.parse(json['amount']?.toString() ?? json['amountMinor']?.toString() ?? '0'),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}
