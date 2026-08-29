class AppNotification {
  const AppNotification({required this.id, required this.type, required this.title, required this.message, required this.createdAt, this.readAt, this.data});
  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic>? data;
  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'SYSTEM',
        title: json['title']?.toString() ?? 'Notification',
        message: json['message']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
        data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : null,
      );
}
