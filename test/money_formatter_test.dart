import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';

void main() {
  test('formats minor units as ETB', () {
    expect(MoneyFormatter.minorToEtb(BigInt.from(125050)), '1,250.50 ETB');
  });

  test('converts ETB input to minor units', () {
    expect(MoneyFormatter.etbInputToMinor('1250.50'), '125050');
  });
}
