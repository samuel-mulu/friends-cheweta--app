/// A private 1:1 message (durable on the server).
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.text,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String text;
  final DateTime createdAt;
  final DateTime? readAt;

  /// The other participant, seen from [myUserId].
  String peerOf(String myUserId) => senderId == myUserId ? recipientId : senderId;

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] is Map ? Map<String, dynamic>.from(json['sender'] as Map) : const <String, dynamic>{};
    return DirectMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      senderId: sender['userId']?.toString() ?? '',
      senderName: sender['displayName']?.toString() ?? 'Player',
      recipientId: json['recipientId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
    );
  }
}

/// One inbox row.
class Conversation {
  const Conversation({required this.peerId, required this.peerName, required this.lastMessage, required this.unread});

  final String peerId;
  final String peerName;
  final DirectMessage lastMessage;
  final int unread;

  Conversation copyWith({DirectMessage? lastMessage, int? unread}) =>
      Conversation(peerId: peerId, peerName: peerName, lastMessage: lastMessage ?? this.lastMessage, unread: unread ?? this.unread);

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final peer = json['peer'] is Map ? Map<String, dynamic>.from(json['peer'] as Map) : const <String, dynamic>{};
    return Conversation(
      peerId: peer['userId']?.toString() ?? '',
      peerName: peer['displayName']?.toString() ?? 'Player',
      lastMessage: DirectMessage.fromJson(Map<String, dynamic>.from(json['lastMessage'] as Map)),
      unread: int.tryParse(json['unread']?.toString() ?? '') ?? 0,
    );
  }
}
