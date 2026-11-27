import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/variant_picker.dart';

/// The lobby's bottom panel and the practice sheet place the picker in a
/// Column with unbounded height. It must lay out there (it used to throw
/// "BoxConstraints forces an infinite height" and blank the lobby).
void main() {
  for (final game in ['DAMA', 'LUDO']) {
    testWidgets('$game type picker lays out in a bottom panel', (tester) async {
      final variants = GameVariants.of(game);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            VariantPicker(compact: true, variants: variants, selected: variants.first, onChanged: (_) {}),
          ]),
        ),
      ));

      expect(tester.takeException(), isNull);
      final heights = {for (final v in variants) tester.getSize(find.text(v.name)).height > 0};
      expect(heights, {true});
      // Cards stay a sensible height (not stretched to the screen).
      expect(tester.getSize(find.byType(VariantPicker)).height, lessThan(120));
    });
  }
}
