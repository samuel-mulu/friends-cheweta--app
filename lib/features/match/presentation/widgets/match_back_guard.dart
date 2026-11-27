import 'package:flutter/material.dart';

/// The phone's back button on a match screen: it never closes the app or
/// drops a live match silently. [onBack] decides (ask to leave, or open the
/// result of a finished match). Dialogs and sheets on top still close first.
class MatchBackGuard extends StatelessWidget {
  const MatchBackGuard({super.key, required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onBack();
        },
        child: child,
      );
}
