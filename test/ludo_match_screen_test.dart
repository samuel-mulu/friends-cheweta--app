import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/presentation/screens/ludo_match_screen.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';
import 'support/fake_socket.dart';
import 'support/ludo_fixtures.dart';

const _colors = ['RED', 'GREEN', 'YELLOW', 'BLUE'];

LudoRuntimeSnapshot _snapshot(
  List<String> playerIds, {
  String turnPhase = 'WAITING_FOR_ROLL',
  List<String> legal = const [],
  Map<String, int> progress = const {},
}) =>
    LudoRuntimeSnapshot.fromJson({
      'game': {
        'rulesVersion': 'LUDO_CLASSIC_V3',
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
                  tokenJson(
                    '${playerIds.length == 2 ? ['RED', 'YELLOW'][i] : _colors[i]}-$t',
                    id,
                    playerIds.length == 2 ? ['RED', 'YELLOW'][i] : _colors[i],
                    progress['${playerIds.length == 2 ? ['RED', 'YELLOW'][i] : _colors[i]}-$t'] ?? -1,
                  ),
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

Future<ProviderContainer> _pump(WidgetTester tester, List<String> players, {LudoMatchController Function()? match}) async {
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
  return ProviderScope.containerOf(tester.element(find.byType(LudoMatchScreen)));
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

  testWidgets('a walk is drawn hop by hop; the placed token only appears at the end', (tester) async {
    final snapshot = _snapshot(['me', 'p2'], progress: {'RED-1': 3});
    final container = await _pump(tester, ['me', 'p2'], match: () => _FixedMatch(snapshot));
    final timeline = container.read(ludoTimelineProvider.notifier);
    timeline.seed(snapshot);
    await tester.pump();

    Offset redOne() => tester.getCenter(find.byWidgetPredicate((w) => w is LudoTokenPiece && w.baseIndex == 0 && w.color.name == 'red').first);
    final start = redOne();

    timeline.enqueue(moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 3, to: 6, dice: 3, version: 6));
    await tester.pump(); // walker mounted
    await tester.pump(const Duration(milliseconds: 1)); // first frame of the walk
    expect(container.read(ludoTimelineProvider).busy, isTrue);
    final early = redOne();
    expect((early - start).distance, lessThan(12), reason: 'the token starts where it stood, it does not jump');

    await tester.pump(const Duration(milliseconds: 300)); // mid-walk (3 hops × 150 ms)
    final mid = redOne();
    expect((mid - start).distance, greaterThan(12));

    await tester.pump(const Duration(milliseconds: 400)); // walk completes → scene reported
    await tester.pump();
    expect(container.read(ludoTimelineProvider).idle, isTrue);
    expect(container.read(ludoTimelineProvider).presented!.game.tokenById('RED-1')!.progress, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a token reaching home bursts confetti; the result shows a win moment, tap to dismiss', (tester) async {
    final snapshot = _snapshot(['me', 'p2'], progress: {'RED-1': 55});
    final container = await _pump(tester, ['me', 'p2'], match: () => _FixedMatch(snapshot));
    final timeline = container.read(ludoTimelineProvider.notifier);
    timeline.seed(snapshot);
    await tester.pump();

    timeline.enqueue(moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 55, to: 56, dice: 1, version: 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // one hop + settle, then the finish scene
    await tester.pump();
    expect(find.byType(Confetti), findsOneWidget);

    timeline.enqueue(ludoEvent('match:finished', {'winnerOrder': ['me', 'p2']}, version: 7));
    await tester.pump(const Duration(milliseconds: 600)); // finish scene ends, match end starts
    await tester.pump();
    expect(find.byType(WinCelebration), findsOneWidget);
    await tester.tap(find.byType(WinCelebration));
    await tester.pump();
    expect(find.byType(WinCelebration), findsNothing);

    await tester.pump(const Duration(seconds: 4)); // let the timeline and timers finish
    expect(tester.takeException(), isNull);
  });

  testWidgets('the win moment also ends on its own', (tester) async {
    final snapshot = _snapshot(['me', 'p2']);
    final container = await _pump(tester, ['me', 'p2'], match: () => _FixedMatch(snapshot));
    final timeline = container.read(ludoTimelineProvider.notifier);
    timeline.seed(snapshot);
    timeline.enqueue(ludoEvent('match:finished', {'winnerOrder': ['me', 'p2']}, version: 6));
    await tester.pump();
    expect(find.byType(WinCelebration), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(WinCelebration), findsNothing);
  });
}
