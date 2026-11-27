import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The screen stays on while the app is open, so the phone never sleeps in
/// the middle of a match or while waiting in a lobby. It is let go when the
/// app goes to the background and taken again when it comes back.
class ScreenAwake with WidgetsBindingObserver {
  ScreenAwake._();

  static final ScreenAwake _instance = ScreenAwake._();
  static bool _started = false;

  /// Call once after the binding is ready.
  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_instance);
    _set(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _set(state == AppLifecycleState.resumed);

  static Future<void> _set(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // A platform without wake locks: the screen just follows its own timeout.
    }
  }
}
