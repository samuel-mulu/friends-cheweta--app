import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';

void main() {
  test('orders lobby players ready, online, busy with readyAt first', () {
    final state = LiveLobbyState(
      currentUserId: 'me',
      players: [
        const LobbyPlayer(userId: 'busy', displayName: 'Daniel', state: LobbyPlayerState.challenged),
        const LobbyPlayer(userId: 'online', displayName: 'Meron', state: LobbyPlayerState.online),
        LobbyPlayer(
          userId: 'ready-late',
          displayName: 'Hanna',
          state: LobbyPlayerState.ready,
          readyAt: DateTime.parse('2026-10-01T10:01:00Z'),
        ),
        LobbyPlayer(
          userId: 'ready-early',
          displayName: 'Abel',
          state: LobbyPlayerState.ready,
          readyAt: DateTime.parse('2026-10-01T10:00:00Z'),
        ),
        const LobbyPlayer(userId: 'me', displayName: 'Samuel', state: LobbyPlayerState.ready),
      ],
    );

    expect(state.orderedPlayers.map((player) => player.userId),
        ['ready-early', 'ready-late', 'online', 'busy']);
  });

  test('copyWith tracks and clears local lobby chat unread count', () {
    final message = ChatMessage(
      id: 'm1',
      scope: 'LOBBY',
      scopeId: 'mode-1',
      sender: ChatSender(userId: 'u1', displayName: 'Samuel'),
      text: 'ሰላም 👋',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final state = const LiveLobbyState().copyWith(messages: [message], chatUnread: 1);

    expect(state.messages.single.text, 'ሰላም 👋');
    expect(state.chatUnread, 1);
    expect(state.copyWith(chatUnread: 0).chatUnread, 0);
  });

  group('multi-account identity', () {
    test('A+B online: B gets A joined without flipping myState', () {
      var state = const LiveLobbyState(
        currentUserId: 'B',
        myState: LobbyPlayerState.online,
        players: [
          LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.online, isSelf: true),
        ],
      );

      state = state.upsertPlayer(
        const LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.online),
      );

      expect(state.myState, LobbyPlayerState.online);
      expect(state.orderedPlayers.map((p) => p.userId), ['A']);
      expect(state.players.singleWhere((p) => p.userId == 'A').isSelf, isFalse);
    });

    test('A READY while current user is B keeps B ONLINE and shows A', () {
      var state = const LiveLobbyState(
        currentUserId: 'B',
        myState: LobbyPlayerState.online,
        players: [
          LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.online),
          LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.online),
        ],
      );

      state = state.upsertPlayer(
        const LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.ready),
      );

      expect(state.myState, LobbyPlayerState.online);
      expect(state.players.singleWhere((p) => p.userId == 'A').state, LobbyPlayerState.ready);
      expect(state.orderedPlayers.map((p) => p.userId), contains('A'));
      expect(state.readyCount, 1);
      expect(state.onlineCount, 2);
    });

    test('B READY updates myState for current user B', () {
      var state = const LiveLobbyState(
        currentUserId: 'B',
        myState: LobbyPlayerState.online,
        players: [
          LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.ready),
          LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.online),
        ],
      );

      state = state.upsertPlayer(
        const LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.ready),
      );

      expect(state.myState, LobbyPlayerState.ready);
      expect(state.selfPlayer?.userId, 'B');
      expect(state.orderedPlayers.map((p) => p.userId), ['A']);
    });

    test('malformed foreign isSelf:true does not become self', () {
      var state = const LiveLobbyState(
        currentUserId: 'B',
        myState: LobbyPlayerState.online,
        players: [
          LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.online),
        ],
      );

      state = state.upsertPlayer(
        const LobbyPlayer(
          userId: 'A',
          displayName: 'Abel',
          state: LobbyPlayerState.ready,
          isSelf: true, // hostile / buggy server payload
        ),
      );

      expect(state.myState, LobbyPlayerState.online);
      expect(state.players.singleWhere((p) => p.userId == 'A').isSelf, isFalse);
      expect(state.selfPlayer?.userId, 'B');
      expect(state.orderedPlayers.map((p) => p.userId), contains('A'));
    });

    test('three-user busy: C myState unchanged when A and B become busy', () {
      var state = const LiveLobbyState(
        currentUserId: 'C',
        myState: LobbyPlayerState.online,
        players: [
          LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.ready),
          LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.ready),
          LobbyPlayer(userId: 'C', displayName: 'Chaltu', state: LobbyPlayerState.online),
        ],
      );

      state = state.markPlayer('A', LobbyPlayerState.challenged);
      state = state.markPlayer('B', LobbyPlayerState.challenged);

      expect(state.myState, LobbyPlayerState.online);
      expect(state.players.singleWhere((p) => p.userId == 'A').state, LobbyPlayerState.challenged);
      expect(state.players.singleWhere((p) => p.userId == 'B').state, LobbyPlayerState.challenged);
      expect(state.players.singleWhere((p) => p.userId == 'C').state, LobbyPlayerState.online);
    });

    test('player_left removes peer without changing myState', () {
      var state = const LiveLobbyState(
        currentUserId: 'B',
        myState: LobbyPlayerState.ready,
        players: [
          LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.ready),
          LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.ready),
        ],
      );

      state = state.removePlayer('A');

      expect(state.myState, LobbyPlayerState.ready);
      expect(state.players.map((p) => p.userId), ['B']);
    });

    test('account switch defense: currentUserId B ignores A as self', () {
      final state = const LiveLobbyState(currentUserId: 'B').withNormalizedPlayers(const [
        LobbyPlayer(userId: 'A', displayName: 'Abel', state: LobbyPlayerState.ready, isSelf: true),
        LobbyPlayer(userId: 'B', displayName: 'Berhanu', state: LobbyPlayerState.online, isSelf: false),
      ]);

      expect(state.selfPlayer?.userId, 'B');
      expect(state.players.singleWhere((p) => p.userId == 'A').isSelf, isFalse);
      expect(state.players.singleWhere((p) => p.userId == 'B').isSelf, isTrue);
    });
  });
}
