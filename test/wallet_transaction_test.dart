import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/wallet/domain/wallet_transaction.dart';

WalletTransaction _tx(String type, {String? delta}) => WalletTransaction.fromJson({
      'id': 't1',
      'type': type,
      'amountMinor': '5000',
      'createdAt': '2026-11-17T10:27:00Z',
      if (delta != null) 'availableDelta': delta,
    });

void main() {
  test('the ledger delta decides the direction (a stake shows once as money out)', () {
    expect(_tx('GAME_ENTRY_LOCK', delta: '-5000').flow, MoneyFlow.outflow);
    expect(_tx('GAME_ENTRY_SPEND', delta: '0').flow, MoneyFlow.neutral);
    expect(_tx('GAME_WIN', delta: '10000').flow, MoneyFlow.inflow);
    expect(_tx('ADMIN_ADJUSTMENT', delta: '-200').flow, MoneyFlow.outflow);
  });

  test('older payloads without a delta fall back to the type', () {
    expect(_tx('DEPOSIT').flow, MoneyFlow.inflow);
    expect(_tx('GAME_ENTRY_LOCK').flow, MoneyFlow.outflow);
    expect(_tx('GAME_ENTRY_SPEND').flow, MoneyFlow.neutral);
  });

  test('rows read as plain words', () {
    expect(_tx('GAME_ENTRY_LOCK').label, 'Match stake');
    expect(_tx('GAME_WIN').label, 'Match win');
    expect(_tx('SOMETHING_NEW').label, 'Something new');
  });
}
