import 'package:intl/intl.dart';

abstract final class MoneyFormatter {
  static String minorToEtb(BigInt amountMinor) {
    final negative = amountMinor.isNegative;
    final absolute = amountMinor.abs();
    final whole = absolute ~/ BigInt.from(100);
    final cents = (absolute % BigInt.from(100)).toInt();
    final grouped = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '${negative ? '-' : ''}$grouped.${cents.toString().padLeft(2, '0')} ETB';
  }

  /// Short form for chips and pills: "10 ETB", "12.50 ETB", "1,250 ETB".
  static String compactEtb(int amountMinor) {
    final whole = amountMinor ~/ 100;
    final cents = amountMinor.abs() % 100;
    final wholeText = NumberFormat('#,##0', 'en_US').format(whole);
    return cents == 0 ? '$wholeText ETB' : '$wholeText.${cents.toString().padLeft(2, '0')} ETB';
  }

  static String etbInputToMinor(String input) {
    final normalized = input.trim().replaceAll(',', '');
    final amount = double.parse(normalized);
    return (amount * 100).round().toString();
  }
}
