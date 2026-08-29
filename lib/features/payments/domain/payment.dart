enum PaymentStatus { pending, approved, rejected, unknown }

PaymentStatus paymentStatusFrom(String? value) => switch (value?.toUpperCase()) {
  'PENDING' => PaymentStatus.pending,
  'APPROVED' => PaymentStatus.approved,
  'REJECTED' => PaymentStatus.rejected,
  _ => PaymentStatus.unknown,
};

class PaymentSubmission {
  const PaymentSubmission({required this.id, required this.status});
  final String id;
  final PaymentStatus status;

  factory PaymentSubmission.fromJson(Map<String, dynamic> json) => PaymentSubmission(
        id: json['id']?.toString() ?? '',
        status: paymentStatusFrom(json['status']?.toString()),
      );
}
