enum PaymentStatus { pending, approved, rejected, paid, unknown }

PaymentStatus paymentStatusFrom(String? value) =>
    switch (value?.toUpperCase()) {
      'PENDING' => PaymentStatus.pending,
      'APPROVED' => PaymentStatus.approved,
      'REJECTED' => PaymentStatus.rejected,
      'PAID' => PaymentStatus.paid,
      _ => PaymentStatus.unknown,
    };

String paymentChannelLabel(String channel) => switch (channel) {
      'TELEBIRR' => 'Telebirr',
      'AWASH' => 'Awash',
      'BOA' => 'Bank of Abyssinia',
      _ => channel,
    };

String depositIssueLabel(String? code) => switch (code) {
      'INVALID_RECEIPT' => 'This receipt could not be confirmed.',
      'AMOUNT_MISMATCH' =>
        'The receipt amount differs from the entered amount.',
      'SETTLEMENT_MISMATCH' =>
        'The receipt recipient differs from the settlement account.',
      'VERIFICATION_PENDING' => 'The provider is still verifying this receipt.',
      'VERIFICATION_UNAVAILABLE' =>
        'Receipt verification is temporarily unavailable.',
      'VERIFICATION_CANCELLED' => 'Verification was cancelled.',
      'VERIFICATION_EXPIRED' =>
        'Verification expired. You can submit the receipt again.',
      _ => 'The receipt is waiting for verification.',
    };

String? paymentAmountMinor(String? value) {
  final match = RegExp(r'^(\d{1,16})(?:\.(\d{1,2}))?$')
      .firstMatch(value?.trim().replaceAll(',', '') ?? '');
  if (match == null) return null;
  final amount = BigInt.parse(match.group(1)!) * BigInt.from(100) +
      BigInt.parse((match.group(2) ?? '').padRight(2, '0'));
  return amount > BigInt.zero ? amount.toString() : null;
}

class DepositProvider {
  const DepositProvider(
      {required this.channel,
      required this.approvalMode,
      required this.account,
      required this.receiver});

  final String channel;
  final String approvalMode;
  final String account;
  final String receiver;

  factory DepositProvider.fromJson(Map<String, dynamic> json) =>
      DepositProvider(
        channel: json['channel'] as String,
        approvalMode: json['approvalMode'] as String,
        account: json['account'] as String? ?? '',
        receiver: json['receiverName'] as String? ?? '',
      );
}

class PaymentSubmission {
  const PaymentSubmission({
    required this.id,
    required this.status,
    this.amountMinor,
    this.channel,
    this.reference,
    this.verificationStatus,
    this.verificationCode,
    this.rejectionReason,
    this.createdAt,
  });

  final String id;
  final PaymentStatus status;
  final String? amountMinor;
  final String? channel;
  final String? reference;
  final String? verificationStatus;
  final String? verificationCode;
  final String? rejectionReason;
  final DateTime? createdAt;

  bool get canCheck =>
      status == PaymentStatus.pending && verificationStatus != null;

  String statusLabel({required bool withdrawal}) => switch (status) {
        PaymentStatus.pending => canCheck ? 'Verifying' : 'Pending review',
        PaymentStatus.approved => withdrawal ? 'Legacy approval' : 'Approved',
        PaymentStatus.rejected => switch (verificationStatus) {
            'CANCELLED' => 'Cancelled',
            'EXPIRED' => 'Expired',
            _ => 'Rejected',
          },
        PaymentStatus.paid => 'Paid',
        PaymentStatus.unknown => 'Status unavailable',
      };

  factory PaymentSubmission.fromJson(Map<String, dynamic> json) =>
      PaymentSubmission(
        id: json['id']?.toString() ?? '',
        status: paymentStatusFrom(json['status']?.toString()),
        amountMinor: json['amountMinor']?.toString(),
        channel: json['channel']?.toString(),
        reference:
            (json['transactionReference'] ?? json['destination'])?.toString(),
        verificationStatus: json['verificationStatus']?.toString(),
        verificationCode: json['lastVerificationCode']?.toString(),
        rejectionReason: json['rejectionReason']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}
