import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_event_reducer.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/goal_picker.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';
import 'support/fake_socket.dart';

const _mode = GameMode(
  id: 'mode-1',
  gameId: 'g',
  code: 'LUDO_1V1',
  name: 'Ludo',
  playerCount: 2,
  stakeAmountMinor: 100,
  platformFeeBps: 0,
  turnDurationSeconds: 30,
  rulesVersion: 'LUDO_CLASSIC_V1',
  enabled: true,
);

Map<String, dynamic> _token(String id, String state, int progress) =>
    {'id': id, 'ownerId': 'p2', 'color': 'YELLOW', 'state': state, 'progress': progress};

void main() {
  testWidgets('goal picker returns the chosen goal and remembers it', (tester) async {
    int? picked;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await pickGoal(context, confirmLabel: 'Connect'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('All 4 home'), findsOneWidget); // classic is the default

    await tester.tap(find.bySemanticsLabel('First to 2 home, Short'));
    await tester.pump();
    expect(find.text('First to 2 home'), findsOneWidget);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(picked, 2);
    final container = ProviderScope.containerOf(tester.element(find.text('open')));
    expect(container.read(playerPreferencesProvider).tokensToWin, 2);
  });

  test('Connect sends the chosen goal; challenges carry it back', () async {
    final socket = FakeSocket();
    Map<String, dynamic>? sent;
    socket.reply = (event, payload) {
      if (event == 'challenge:create') sent = payload;
      return {'ok': true};
    };
    final container = ProviderContainer(overrides: [
      gameSocketServiceProvider.overrideWithValue(socket),
      authControllerProvider.overrideWith(SignedInAs.new),
    ]);
    addTearDown(container.dispose);
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    await lobby.challenge(
      const LobbyPlayer(userId: 'sam', displayName: 'Sam', state: LobbyPlayerState.ready),
      tokensToWin: 3,
    );
    expect(sent?['tokensToWin'], 3);

    expect(LobbyChallenge.fromJson({'id': 'c', 'tokensToWin': 2}).tokensToWin, 2);
    expect(LobbyChallenge.fromJson({'id': 'c'}).tokensToWin, 4); // older servers
  });

  test('a finished player retires their unfinished tokens to the yard', () {
    final snapshot = LudoRuntimeSnapshot.fromJson({
      'game': {
        'matchId': 'm1',
        'version': 3,
        'phase': 'PLAYING',
        'turnPhase': 'WAITING_FOR_ROLL',
        'currentPlayerId': 'p2',
        'legalTokenIds': [],
        'tokensToWin': 1,
        'players': [
          {
            'userId': 'p2',
            'color': 'YELLOW',
            'tokens': [_token('YELLOW-1', 'FINISHED', 57), _token('YELLOW-2', 'ACTIVE', 12)],
          },
        ],
      },
      'startingRoll': {'round': 1, 'candidatePlayerIds': [], 'rolls': {}},
      'resignedPlayerIds': [],
    });
    expect(snapshot.game.tokensToWin, 1);
    expect(snapshot.game.tokensHome('p2'), 1);

    final next = reduceLudoEvent(
      snapshot,
      const RealtimeEvent(name: 'ludo:player_finished', payload: {
        'data': {
          'playerId': 'p2',
          'tokenIds': ['YELLOW-2'],
        },
      }),
      4,
    );
    expect(next.game.winnerOrder, ['p2']);
    expect(next.game.tokenById('YELLOW-2')?.state, LudoTokenState.base);
    expect(next.game.tokensToWin, 1); // survives copyWith
  });

  testWidgets('a seat shows goal progress as crowns', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LudoSeat(
          seat: LudoSeatView(
            participant: LudoMatchParticipant(userId: 'me', fullName: 'Me', seat: 0, color: LudoColor.red),
            corner: LudoCorner.bottomLeft,
            isMe: true,
            active: false,
            diceValue: null,
            diceKey: 0,
            diceState: LudoDiceVisualState.disabled,
            tokensHome: 1,
            tokensToWin: 2,
          ),
        ),
      ),
    ));
    expect(find.bySemanticsLabel('1 of 2 tokens home'), findsOneWidget);
  });
}
