import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/features/auth/data/auth_repository.dart';
import 'package:friends_game_app/features/auth/presentation/screens/password_screen.dart';
import 'package:friends_game_app/features/payments/data/payment_repository.dart';
import 'package:friends_game_app/features/payments/domain/payment.dart';
import 'package:friends_game_app/features/payments/presentation/screens/deposit_screen.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

void main() {
  testWidgets(
      'forgot password requests an SMS and submits the selected phone and code',
      (tester) async {
    final auth = _AuthRepository();
    final router = GoRouter(
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(
            path: '/forgot-password',
            builder: (_, __) =>
                const PasswordScreen.reset(initialPhone: '0911234567')),
        GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('Sign in'))),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp.router(routerConfig: router),
    ));

    await tester.tap(find.text('Send SMS code'));
    await tester.pumpAndSettle();
    expect(auth.requestedPhone, '0911234567');
    expect(find.text('Resend in 30s'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '0427');
    await tester.enterText(fields.at(2), 'new-password');
    await tester.enterText(fields.at(3), 'new-password');
    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(auth.resetRequest, ('0911234567', '0427', 'new-password'));
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets(
      'deposit screen resumes a pending server attempt and shows the credited result',
      (tester) async {
    final payments = _PaymentRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paymentRepositoryProvider.overrideWithValue(payments),
        walletControllerProvider.overrideWith(_WalletController.new),
      ],
      child: const MaterialApp(home: DepositScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Telebirr verification'), findsOneWidget);
    expect(find.text('The provider is still verifying this receipt.'),
        findsOneWidget);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(payments.checkedId, 'pending-local-deposit');
    expect(find.text('Your wallet has been credited.'), findsOneWidget);
    expect(find.text('Check again'), findsNothing);
  });
}

class _AuthRepository implements AuthRepository {
  String? requestedPhone;
  (String, String, String)? resetRequest;

  @override
  Future<void> requestOtp(String phoneNumber, {required bool reset}) async {
    expect(reset, true);
    requestedPhone = phoneNumber;
  }

  @override
  Future<void> resetPassword(
      String phoneNumber, String otp, String newPassword) async {
    resetRequest = (phoneNumber, otp, newPassword);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PaymentRepository implements PaymentRepository {
  static const attempt = PaymentSubmission(
    id: 'pending-local-deposit',
    status: PaymentStatus.pending,
    channel: 'TELEBIRR',
    amountMinor: '1250',
    verificationStatus: 'AWAITING_PROVIDER',
    verificationCode: 'VERIFICATION_PENDING',
  );
  String? checkedId;

  @override
  Future<List<DepositProvider>> depositConfig() async => const [
        DepositProvider(
            channel: 'TELEBIRR',
            approvalMode: 'AUTOMATIC',
            account: '251911234567',
            receiver: 'Cheweta'),
      ];

  @override
  Future<List<PaymentSubmission>> activeAttempts() async =>
      checkedId == null ? [attempt] : [];

  @override
  Future<PaymentSubmission> updateAttempt(String id,
      {required bool cancel}) async {
    expect(cancel, false);
    checkedId = id;
    return PaymentSubmission(
        id: id,
        status: PaymentStatus.approved,
        verificationStatus: 'SUCCEEDED');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletController extends WalletController {
  @override
  WalletViewState build() => const WalletViewState();

  @override
  Future<void> refresh() async {}
}
