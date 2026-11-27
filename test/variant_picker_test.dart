import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/variant_picker.dart';

/// The type cards live in places without a height limit (the lobby's ready
/// panel, the practice sheet's scroll view). They must lay out there, with
/// two or three types, on a small phone with large text.
void main() {
  for (final gameCode in ['DAMA', 'LUDO']) {
    testWidgets('$gameCode type cards lay out in an unbounded column', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      GameVariant? picked;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: const SizedBox.expand(),
            // Like the lobby: a bottom panel whose column is as tall as its content.
            bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
              VariantPicker(
                compact: true,
                variants: GameVariants.of(gameCode),
                selected: GameVariants.defaultOf(gameCode),
                onChanged: (v) => picked = v,
              ),
              GoalChips(selected: 4, onChanged: (_) {}),
            ]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);

      // Like the practice sheet: inside a scroll view.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: VariantPicker(variants: GameVariants.of(gameCode), selected: null, onChanged: (v) => picked = v),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel(RegExp(GameVariants.of(gameCode).last.name)));
      expect(picked, GameVariants.of(gameCode).last);
    });
  }
}
