import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_dice.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';

void main() {
  group('UI1 locked playfield layout', () {
    testWidgets('board stays square at 320px width without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 52, child: ColoredBox(color: Colors.grey)),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = constraints.maxWidth < constraints.maxHeight
                            ? constraints.maxWidth
                            : constraints.maxHeight;
                        return Center(
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: const LudoBoard(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 52, child: ColoredBox(color: Colors.grey)),
                  const SizedBox(height: 120, child: ColoredBox(color: Colors.blueGrey)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final boardSize = tester.getSize(find.byType(LudoBoard));
      expect(boardSize.width, closeTo(boardSize.height, 0.5));
      expect(boardSize.width, lessThanOrEqualTo(320));
    });

    testWidgets('playfield column is not scroll-dependent', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: LudoBoard()),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(LudoBoard), findsOneWidget);
    });
  });

  group('UI3 dice', () {
    testWidgets('renders pip faces 1-6', (tester) async {
      for (var face = 1; face <= 6; face++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: LudoDiceFace(value: face, size: 48)),
            ),
          ),
        );
        expect(find.byType(LudoDiceFace), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('disabled/waiting dice is not tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LudoDice(
                value: 3,
                animateKey: 0,
                state: LudoDiceVisualState.waiting,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(LudoDice));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('ready dice invokes onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LudoDice(
                value: null,
                animateKey: 0,
                state: LudoDiceVisualState.ready,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Roll dice'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('authoritative final value settles after animateKey bump', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LudoDice(
                value: 5,
                animateKey: 1,
                state: LudoDiceVisualState.result,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LudoDice(
                value: 5,
                animateKey: 2,
                state: LudoDiceVisualState.result,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.byType(LudoDice), findsOneWidget);
    });
  });

  group('UI4 tokens and stacking', () {
    testWidgets('legal token is selectable; illegal is not', (tester) async {
      var legalTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                LudoTokenPiece(
                  color: LudoColor.red,
                  size: 40,
                  baseIndex: 0,
                  highlighted: true,
                  onTap: () => legalTaps += 1,
                ),
                const LudoTokenPiece(
                  color: LudoColor.blue,
                  size: 40,
                  baseIndex: 1,
                  highlighted: false,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(LudoTokenPiece).first);
      await tester.pump();
      expect(legalTaps, 1);

      await tester.tap(find.byType(LudoTokenPiece).last);
      await tester.pump();
      expect(legalTaps, 1);
    });

    test('stack offsets are distinct for 2 and 4 tokens', () {
      const cell = 20.0;
      final two = [
        LudoBoardGeometry.stackOffset(stackIndex: 0, stackCount: 2, cellSize: cell),
        LudoBoardGeometry.stackOffset(stackIndex: 1, stackCount: 2, cellSize: cell),
      ];
      expect(two[0], isNot(equals(two[1])));

      final four = [
        for (var i = 0; i < 4; i++) LudoBoardGeometry.stackOffset(stackIndex: i, stackCount: 4, cellSize: cell),
      ];
      final unique = four.toSet();
      expect(unique.length, 4);
    });

    test('base tokens ignore track stacking and use pocket spots', () {
      final a = LudoBoardGeometry.tokenCenter(
        color: LudoColor.red,
        progress: -1,
        baseIndex: 0,
        boardSize: 300,
        stackIndex: 0,
        stackCount: 4,
      );
      final b = LudoBoardGeometry.tokenCenter(
        color: LudoColor.red,
        progress: -1,
        baseIndex: 1,
        boardSize: 300,
        stackIndex: 1,
        stackCount: 4,
      );
      expect(a, isNot(equals(b)));
    });

    testWidgets('board highlights only legal tokens via view model', (tester) async {
      var moved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LudoBoard(
              tokens: [
                LudoBoardTokenView(
                  id: 't1',
                  color: LudoColor.red,
                  progress: 3,
                  baseIndex: 0,
                  highlighted: true,
                  onTap: () => moved = true,
                ),
                const LudoBoardTokenView(
                  id: 't2',
                  color: LudoColor.red,
                  progress: 4,
                  baseIndex: 1,
                  highlighted: false,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(LudoTokenPiece).first);
      await tester.pump();
      expect(moved, isTrue);
    });
  });
}
