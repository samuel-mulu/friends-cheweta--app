class ChatSender {
  const ChatSender({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  factory ChatSender.fromJson(Map<String, dynamic> json) => ChatSender(
        userId: json['userId']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? 'Player',
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String scope;
  final String scopeId;
  final ChatSender sender;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSender = json['sender'];
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      scopeId: json['scopeId']?.toString() ?? '',
      sender: rawSender is Map ? ChatSender.fromJson(Map<String, dynamic>.from(rawSender)) : const ChatSender(userId: '', displayName: 'Player'),
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
    );
  }
}
