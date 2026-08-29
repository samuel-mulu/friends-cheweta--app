class Wallet {
  const Wallet({required this.availableBalance, required this.lockedBalance, required this.currency});

  final BigInt availableBalance;
  final BigInt lockedBalance;
  final String currency;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        availableBalance: BigInt.parse(json['availableBalance'].toString()),
        lockedBalance: BigInt.parse(json['lockedBalance'].toString()),
        currency: json['currency']?.toString() ?? 'ETB',
      );
}
