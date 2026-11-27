import 'package:flutter/material.dart';

/// The screen's main action: full width, gold, 52 px. Shows a spinner while
/// [loading]; an [icon] only when it says something the label doesn't.
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final spinner = const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2));
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: icon == null && !loading
          ? FilledButton(onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              onPressed: loading ? null : onPressed,
              icon: loading ? spinner : Icon(icon),
              label: Text(label),
            ),
    );
  }
}
