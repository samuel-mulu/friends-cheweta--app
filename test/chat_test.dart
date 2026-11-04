import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';
import 'package:friends_game_app/features/chat/application/direct_chat_controller.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';
import 'support/fake_socket.dart';

Map<String, dynamic> _dm(String id, String from, String to, String text, {int second = 0}) => {
      'id': id,
      'conversationId': ([from, to]..sort()).join(':'),
      'sender': {'userId': from, 'displayName': from == 'me' ? 'Me' : 'Sam'},
      'recipientId': to,
      'text': text,
      'createdAt': DateTime.utc(2026, 1, 1, 0, 0, second).toIso8601String(),
      'readAt': null,
    };

void main() {
  group('ChatThread', () {
    List<ChatLine> lines(int n) => [
          for (var i = 0; i < n; i++)
            ChatLine(id: '$i', text: 'message $i', senderName: 'Sam', mine: i.isEven, createdAt: DateTime(2026, 1, 1, 0, i)),
        ];

    testWidgets('the newest message is visible without scrolling, even with long history', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatThread(lines: lines(60), onSend: (_) async => true))));
      expect(find.text('message 59').hitTestable(), findsOneWidget);
      expect(find.text('message 0').hitTestable(), findsNothing);
    });

    testWidgets('a failed send puts the text back so nothing typed is lost', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatThread(lines: const [], onSend: (_) async => false))));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
    });
  });

  group('private chat', () {
    late FakeSocket socket;
    late ProviderContainer container;

    setUp(() {
      socket = FakeSocket();
      container = ProviderContainer(overrides: [
        gameSocketServiceProvider.overrideWithValue(socket),
        authControllerProvider.overrideWith(SignedInAs.new),
      ]);
    });
    tearDown(() => container.dispose());

    test('incoming message raises the unread badge; reading clears it', () async {
      container.read(chatInboxControllerProvider);
      socket.push('chat:direct:message', _dm('1', 'sam', 'me', 'hi'));
      await flush();
      expect(container.read(chatInboxControllerProvider).unreadTotal, 1);
      expect(container.read(chatInboxControllerProvider).conversations.single.peerName, 'Sam');

      socket.push('chat:direct:read', {'peerId': 'sam'});
      await flush();
      expect(container.read(chatInboxControllerProvider).unreadTotal, 0);
    });

    test('an open conversation receives messages live, marks them read and does not bump unread', () async {
      socket.reply = (event, payload) => switch (event) {
            'chat:direct:history' => {'ok': true, 'data': [_dm('1', 'sam', 'me', 'hey', second: 1)]},
            _ => {'ok': true},
          };
      final sub = container.listen(directChatControllerProvider('sam'), (_, __) {});
      await flush();
      await flush();
      expect(container.read(directChatControllerProvider('sam')).messages.map((m) => m.text), ['hey']);

      socket.sent.clear();
      socket.push('chat:direct:message', _dm('2', 'sam', 'me', 'you there?', second: 2));
      await flush();
      expect(container.read(directChatControllerProvider('sam')).messages.map((m) => m.text), ['hey', 'you there?']);
      expect(socket.sent, contains('chat:direct:read'));
      expect(container.read(chatInboxControllerProvider).unreadTotal, 0);
      sub.close();
    });

    test('sending appends once even when the ack and the event both arrive', () async {
      final sent = _dm('9', 'me', 'sam', 'gg', second: 5);
      socket.reply = (event, _) => switch (event) {
            'chat:direct:history' => {'ok': true, 'data': []},
            'chat:direct:send' => {'ok': true, 'data': sent},
            _ => {'ok': true},
          };
      final sub = container.listen(directChatControllerProvider('sam'), (_, __) {});
      await flush();
      expect(await container.read(directChatControllerProvider('sam').notifier).send('gg'), isTrue);
      socket.push('chat:direct:message', sent);
      await flush();
      expect(container.read(directChatControllerProvider('sam')).messages, hasLength(1));
      sub.close();
    });
  });
}
