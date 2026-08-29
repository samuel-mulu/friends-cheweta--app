import 'package:intl/intl.dart';

abstract final class MoneyFormatter {
  static final _formatter = NumberFormat('#,##0.00', 'en_US');

  static String minorToEtb(BigInt amountMinor) {
    final negative = amountMinor.isNegative;
    final absolute = amountMinor.abs();
    final whole = absolute ~/ BigInt.from(100);
    final cents = (absolute % BigInt.from(100)).toInt();
    final numeric = double.parse('$whole.${cents.toString().padLeft(2, '0')}');
    return '${negative ? '-' : ''}${_formatter.format(numeric)} ETB';
  }

  static String etbInputToMinor(String input) {
    final normalized = input.trim().replaceAll(',', '');
    final amount = double.parse(normalized);
    return (amount * 100).round().toString();
  }
}
