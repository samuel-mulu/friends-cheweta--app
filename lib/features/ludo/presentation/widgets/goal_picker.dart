import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/crown_icon.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

/// "First to N home" as short text, e.g. "First to 2 home".
String goalLabel(int tokensToWin) => tokensToWin >= 4 ? 'All 4 home' : 'First to $tokensToWin home';

/// Asks how many tokens must reach home to win (1-4). Starts from the
/// player's last choice and remembers the new one. Null = cancelled.
Future<int?> pickGoal(BuildContext context, {required String confirmLabel}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final initial = container.read(playerPreferencesProvider).tokensToWin;
  final goal = await showDialog<int>(
    context: context,
    builder: (context) => GoalPickerDialog(initial: initial, confirmLabel: confirmLabel),
  );
  if (goal != null) await container.read(playerPreferencesProvider.notifier).setTokensToWin(goal);
  return goal;
}

class GoalPickerDialog extends StatefulWidget {
  const GoalPickerDialog({super.key, required this.initial, required this.confirmLabel});
  final int initial;
  final String confirmLabel;

  @override
  State<GoalPickerDialog> createState() => _GoalPickerDialogState();
}

class _GoalPickerDialogState extends State<GoalPickerDialog> {
  late int _goal = widget.initial.clamp(1, 4).toInt();

  static const _captions = {1: 'Quick', 2: 'Short', 3: 'Long', 4: 'Classic'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('How many tokens to win?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('The first player to bring this many tokens home wins.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          // Two rows of two (a GridView can't size itself inside a dialog).
          for (final row in const [
            [1, 2],
            [3, 4],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 92,
                child: Row(children: [
                  for (final n in row) ...[
                    if (n != row.first) const SizedBox(width: 10),
                    Expanded(
                      child: _GoalOption(
                        goal: n,
                        caption: _captions[n]!,
                        selected: n == _goal,
                        onTap: () => setState(() => _goal = n),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          const SizedBox(height: 4),
          Text(goalLabel(_goal), textAlign: TextAlign.center, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _goal), child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _GoalOption extends StatelessWidget {
  const _GoalOption({required this.goal, required this.caption, required this.selected, required this.onTap});
  final int goal;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${goalLabel(goal)}, $caption',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(child: CrownRow(count: goal, size: 22)),
                  const SizedBox(height: 6),
                  Text('$goal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Text(caption, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
