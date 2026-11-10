class User {
  const User({required this.id, required this.fullName, required this.phoneNumber, required this.role, required this.status});

  final String id;
  final String fullName;
  final String phoneNumber;
  final String role;
  final String status;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'].toString(),
        fullName: json['fullName']?.toString() ?? '',
        phoneNumber: json['phoneNumber']?.toString() ?? '',
        role: json['role']?.toString() ?? 'PLAYER',
        status: json['status']?.toString() ?? 'ACTIVE',
      );

  Map<String, dynamic> toJson() => {'id': id, 'fullName': fullName, 'phoneNumber': phoneNumber, 'role': role, 'status': status};
}
