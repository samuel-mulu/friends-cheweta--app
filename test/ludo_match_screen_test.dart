import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/presentation/screens/ludo_match_screen.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';
import 'support/fake_socket.dart';

const _colors = ['RED', 'GREEN', 'YELLOW', 'BLUE'];

LudoRuntimeSnapshot _snapshot(List<String> playerIds, {String turnPhase = 'WAITING_FOR_ROLL', List<String> legal = const []}) =>
    LudoRuntimeSnapshot.fromJson({
      'game': {
        'matchId': 'm1',
        'version': 5,
        'phase': 'PLAYING',
        'turnPhase': turnPhase,
        'diceValue': legal.isEmpty ? null : 6,
        'legalTokenIds': legal,
        'currentPlayerId': 'me',
        'players': [
          for (final (i, id) in playerIds.indexed)
            {
              'userId': id,
              'color': playerIds.length == 2 ? ['RED', 'YELLOW'][i] : _colors[i],
              'tokens': [
                for (var t = 1; t <= 4; t++)
                  {
                    'id': '${playerIds.length == 2 ? ['RED', 'YELLOW'][i] : _colors[i]}-$t',
                    'ownerId': id,
                    'color': playerIds.length == 2 ? ['RED', 'YELLOW'][i] : _colors[i],
                    'state': 'BASE',
                    'progress': -1,
                  },
              ],
            },
        ],
      },
      'startingRoll': {'round': 1, 'candidatePlayerIds': playerIds, 'rolls': {}},
      'resignedPlayerIds': [],
    });

class _FixedMatch extends LudoMatchController {
  _FixedMatch(this.snapshot, {this.legalMoves = const [], this.strikes = const {}});
  final LudoRuntimeSnapshot snapshot;
  final List<LudoMovePreview> legalMoves;
  final Map<String, int> strikes;

  @override
  LudoMatchViewState build() {
    super.build();
    return LudoMatchViewState(
      matchId: 'm1',
      snapshot: snapshot,
      participants: [
        for (final (i, p) in snapshot.game.players.indexed)
          LudoMatchParticipant(userId: p.userId, fullName: 'Player ${p.userId}', seat: i, color: p.color),
      ],
      legalMoves: legalMoves,
      strikes: strikes,
    );
  }

  @override
  Future<void> join(String matchId) async {}
}

class _QuietChat extends MatchChatController {
  @override
  Future<void> load(String matchId) async {}
}

Future<void> _pump(WidgetTester tester, List<String> players, {LudoMatchController Function()? match}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final socket = FakeSocket();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gameSocketServiceProvider.overrideWithValue(socket),
      authControllerProvider.overrideWith(SignedInAs.new),
      ludoMatchControllerProvider.overrideWith(match ?? () => _FixedMatch(_snapshot(players))),
      matchChatControllerProvider.overrideWith(_QuietChat.new),
      gameSoundServiceProvider.overrideWithValue(GameSoundService(null)),
    ],
    child: const MaterialApp(home: LudoMatchScreen(matchId: 'm1')),
  ));
  await tester.pump();
}

void main() {
  testWidgets('2 players fit a small phone: me bottom-left, opponent top-right', (tester) async {
    await _pump(tester, ['me', 'p2']);
    expect(tester.takeException(), isNull);
    expect(find.byType(LudoSeat), findsNWidgets(2));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget);
    expect(find.text('Tap your dice to roll'), findsOneWidget);
    final seats = tester.widgetList<LudoSeat>(find.byType(LudoSeat)).toList();
    final me = tester.getCenter(find.byWidget(seats.firstWhere((w) => w.seat.isMe)));
    final opponent = tester.getCenter(find.byWidget(seats.firstWhere((w) => !w.seat.isMe)));
    expect(me.dx, lessThan(180));
    expect(me.dy, greaterThan(opponent.dy));
    expect(opponent.dx, greaterThan(180));
  });

  testWidgets('4 players get one seat per corner without overflow', (tester) async {
    await _pump(tester, ['me', 'p2', 'p3', 'p4']);
    expect(tester.takeException(), isNull);
    expect(find.byType(LudoSeat), findsNWidgets(4));
  });

  testWidgets('on my move, landing previews show where each token would go (capture marked)', (tester) async {
    await _pump(
      tester,
      ['me', 'p2'],
      match: () => _FixedMatch(
        _snapshot(['me', 'p2'], turnPhase: 'WAITING_FOR_MOVE', legal: ['RED-1', 'RED-2']),
        legalMoves: const [
          LudoMovePreview(tokenId: 'RED-1', toProgress: 0, captures: [], safe: true),
          LudoMovePreview(tokenId: 'RED-2', toProgress: 0, captures: ['YELLOW-1'], safe: false),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Move RED-1 here, safe square'), findsOneWidget);
    expect(find.bySemanticsLabel('Move RED-2 here, captures'), findsOneWidget);
    expect(find.text('Tap a glowing token to move'), findsOneWidget);
  });

  testWidgets('away strikes appear as dots on the seat', (tester) async {
    await _pump(tester, ['me', 'p2'], match: () => _FixedMatch(_snapshot(['me', 'p2']), strikes: const {'p2': 2}));
    final seats = tester.widgetList<LudoSeat>(find.byType(LudoSeat));
    expect(seats.firstWhere((s) => !s.seat.isMe).seat.strikes, 2);
  });
}
