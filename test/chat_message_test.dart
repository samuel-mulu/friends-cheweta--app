import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';

void main() {
  test('parses lobby and match chat messages with unicode text', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'scope': 'LOBBY',
      'scopeId': 'mode-1',
      'sender': {'userId': 'u1', 'displayName': 'Samuel'},
      'text': 'ሰላም 👋',
      'createdAt': '2026-10-01T08:00:00.000Z',
    });

    expect(message.id, 'm1');
    expect(message.scope, 'LOBBY');
    expect(message.sender.displayName, 'Samuel');
    expect(message.text, 'ሰላም 👋');
  });

  test('history remains oldest to newest when parsed in list order', () {
    final messages = [
      {
        'id': 'old',
        'scope': 'MATCH',
        'scopeId': 'match-1',
        'sender': {'userId': 'u1', 'displayName': 'A'},
        'text': 'old',
        'createdAt': '2026-10-01T08:00:00.000Z',
      },
      {
        'id': 'new',
        'scope': 'MATCH',
        'scopeId': 'match-1',
        'sender': {'userId': 'u2', 'displayName': 'B'},
        'text': 'new',
        'createdAt': '2026-10-01T08:01:00.000Z',
      },
    ].map(ChatMessage.fromJson).toList();

    expect(messages.first.text, 'old');
    expect(messages.last.text, 'new');
  });
}
