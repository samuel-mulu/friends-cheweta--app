enum FailureKind { network, unauthorized, forbidden, validation, business, server, unknown }

class AppFailure implements Exception {
  const AppFailure({required this.kind, required this.message, this.code});

  final FailureKind kind;
  final String message;
  final String? code;

  bool get isAccountBlocked => code == 'ACCOUNT_BLOCKED';
  bool get isInsufficientBalance => code == 'INSUFFICIENT_BALANCE';

  @override
  String toString() => 'AppFailure(kind: $kind, code: $code, message: $message)';
}
