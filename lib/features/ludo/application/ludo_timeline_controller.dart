import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/ludo/application/ludo_event_reducer.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';

/// What the board is showing right now.
///
/// [presented] trails the controller's authoritative snapshot by exactly the
/// scenes still to play; once the timeline is idle the two are equal.
class LudoTimelineState {
  const LudoTimelineState({
    this.presented,
    this.current,
    this.sequence = 0,
    this.pendingCount = 0,
    this.pendingBlocking = false,
    this.speedFactor = 1.0,
    this.epoch = 0,
    this.presentedDice = const {},
    this.diceKeys = const {},
    this.rollHistory = const {},
    this.spinningPlayerId,
    this.currentFromOptimisticTap = false,
  });

  /// The snapshot the board draws. Null until the match is joined.
  final LudoRuntimeSnapshot? presented;

  /// Scene on stage, or null when idle.
  final LudoScene? current;

  /// Increases every time a new scene starts (widgets key their animations on it).
  final int sequence;
  final int pendingCount;
  final bool pendingBlocking;

  /// > 1 while catching up after a backlog: every scene plays this much faster.
  final double speedFactor;

  /// Bumped by [LudoTimelineController.seed]; screens reset local effects on a change.
  final int epoch;

  /// Last die face shown per player, the sequence it was shown at, and recent faces.
  final Map<String, int> presentedDice;
  final Map<String, int> diceKeys;
  final Map<String, List<int>> rollHistory;

  /// Player whose die spins from their tap until their roll is shown.
  final String? spinningPlayerId;

  /// The current dice scene follows the owner's own tap (its sound already played).
  final bool currentFromOptimisticTap;

  bool get busy => current != null;
  bool get idle => current == null && pendingCount == 0;
  bool get blocking => (current?.blocking ?? false) || pendingBlocking;
  bool get isCatchingUp => speedFactor > 1;

  Duration scale(Duration nominal) => LudoMotion.scaled(nominal, speedFactor);

  LudoTimelineState copyWith({
    LudoRuntimeSnapshot? presented,
    LudoScene? current,
    bool clearCurrent = false,
    int? sequence,
    int? pendingCount,
    bool? pendingBlocking,
    double? speedFactor,
    int? epoch,
    Map<String, int>? presentedDice,
    Map<String, int>? diceKeys,
    Map<String, List<int>>? rollHistory,
    String? spinningPlayerId,
    bool clearSpinning = false,
    bool? currentFromOptimisticTap,
  }) =>
      LudoTimelineState(
        presented: presented ?? this.presented,
        current: clearCurrent ? null : current ?? this.current,
        sequence: sequence ?? this.sequence,
        pendingCount: pendingCount ?? this.pendingCount,
        pendingBlocking: pendingBlocking ?? this.pendingBlocking,
        speedFactor: speedFactor ?? this.speedFactor,
        epoch: epoch ?? this.epoch,
        presentedDice: presentedDice ?? this.presentedDice,
        diceKeys: diceKeys ?? this.diceKeys,
        rollHistory: rollHistory ?? this.rollHistory,
        spinningPlayerId: clearSpinning ? null : spinningPlayerId ?? this.spinningPlayerId,
        currentFromOptimisticTap: currentFromOptimisticTap ?? this.currentFromOptimisticTap,
      );
}

/// Plays scenes one at a time and advances the presented snapshot with them.
///
/// Completion comes from the widget that animates the scene (walker, capture
/// flight, die); a timer at twice the nominal time is the safety net so a
/// missed callback can never freeze the board. When more than
/// [fastForwardThreshold] of stage time is queued (reconnect, app resume, a
/// burst from an opponent) everything plays at [fastForwardFactor] until the
/// queue drains; moves and captures are never skipped.
class LudoTimelineController extends Notifier<LudoTimelineState> {
  static const fastForwardThreshold = Duration(milliseconds: 1200);
  static const fastForwardFactor = 2.5;
  static const optimisticSpinCap = Duration(milliseconds: 1500);
  static const _safetyMargin = Duration(milliseconds: 300);

  final List<LudoScene> _queue = [];
  Timer? _safety;
  Timer? _spinCap;
  int _sequence = 0;
  int _epoch = 0;

  @override
  LudoTimelineState build() {
    ref.onDispose(() {
      _safety?.cancel();
      _spinCap?.cancel();
    });
    return const LudoTimelineState();
  }

  /// Join / recovery: drop every pending scene and show [snapshot] as is.
  void seed(LudoRuntimeSnapshot? snapshot) {
    _safety?.cancel();
    _spinCap?.cancel();
    _queue.clear();
    _epoch++;
    _sequence++;
    state = LudoTimelineState(
      presented: snapshot,
      sequence: _sequence,
      epoch: _epoch,
      presentedDice: snapshot == null ? const {} : _diceFromSnapshot(snapshot),
    );
  }

  void enqueue(RealtimeEvent event) {
    if (state.presented == null) return;
    final scenes = scenesForEvent(event);
    if (scenes.isEmpty) return;
    _queue.addAll(scenes);
    if (state.current == null) {
      _startNext();
    } else {
      state = state.copyWith(
        pendingCount: _queue.length,
        pendingBlocking: _queue.any((scene) => scene.blocking),
        speedFactor: _speedFactor(),
      );
    }
  }

  /// A widget finished animating the scene that started at [sequence].
  void completeScene(int sequence) {
    if (sequence != _sequence || state.current == null) return;
    _finishCurrent();
  }

  /// The owner tapped their die: spin at once, for at most [optimisticSpinCap].
  void startOptimisticSpin(String playerId) {
    _spinCap?.cancel();
    state = state.copyWith(spinningPlayerId: playerId);
    _spinCap = Timer(optimisticSpinCap, stopOptimisticSpin);
  }

  void stopOptimisticSpin() {
    _spinCap?.cancel();
    if (state.spinningPlayerId != null) state = state.copyWith(clearSpinning: true);
  }

  void _startNext() {
    _safety?.cancel();
    if (_queue.isEmpty) {
      state = state.copyWith(
        clearCurrent: true,
        pendingCount: 0,
        pendingBlocking: false,
        speedFactor: 1.0,
        currentFromOptimisticTap: false,
      );
      return;
    }

    final speed = _speedFactor();
    final scene = _queue.removeAt(0);
    var presented = state.presented!;
    if (!scene.appliesAtEnd) presented = reducePresented(presented, scene);

    _sequence++;
    var presentedDice = state.presentedDice;
    var diceKeys = state.diceKeys;
    var rollHistory = state.rollHistory;
    var spinning = state.spinningPlayerId;
    var fromTap = false;
    if (scene is LudoDiceScene && scene.playerId != null) {
      final player = scene.playerId!;
      presentedDice = {...presentedDice, player: scene.value};
      diceKeys = {...diceKeys, player: _sequence};
      rollHistory = {...rollHistory, player: [scene.value, ...?rollHistory[player]].take(3).toList(growable: false)};
      if (spinning == player) {
        fromTap = true;
        spinning = null;
        _spinCap?.cancel();
      }
    }

    state = LudoTimelineState(
      presented: presented,
      current: scene,
      sequence: _sequence,
      pendingCount: _queue.length,
      pendingBlocking: _queue.any((item) => item.blocking),
      speedFactor: speed,
      epoch: _epoch,
      presentedDice: presentedDice,
      diceKeys: diceKeys,
      rollHistory: rollHistory,
      spinningPlayerId: spinning,
      currentFromOptimisticTap: fromTap,
    );

    final duration = state.scale(scene.nominal);
    if (duration == Duration.zero) {
      _finishCurrent();
      return;
    }
    final safety = scene.widgetDriven ? duration * 2 + _safetyMargin : duration;
    final sequence = _sequence;
    _safety = Timer(safety, () {
      if (sequence == _sequence) _finishCurrent();
    });
  }

  void _finishCurrent() {
    _safety?.cancel();
    final scene = state.current;
    if (scene == null) return;
    var presented = state.presented!;
    if (scene.appliesAtEnd) presented = reducePresented(presented, scene);
    state = state.copyWith(presented: presented);
    _startNext();
  }

  double _speedFactor() {
    if (state.speedFactor > 1 && _queue.isNotEmpty) return state.speedFactor; // stay fast until drained
    var total = Duration.zero;
    for (final scene in _queue) {
      total += scene.nominal;
    }
    return total > fastForwardThreshold ? fastForwardFactor : 1.0;
  }

  static Map<String, int> _diceFromSnapshot(LudoRuntimeSnapshot snapshot) {
    final dice = Map<String, int>.from(snapshot.startingRoll.rolls);
    final roller = snapshot.game.currentPlayerId;
    final value = snapshot.game.diceValue;
    if (roller != null && value != null) dice[roller] = value;
    return dice;
  }
}

/// Advance the presented snapshot by one scene.
LudoRuntimeSnapshot reducePresented(LudoRuntimeSnapshot snapshot, LudoScene scene) => switch (scene) {
      LudoMoveScene(:final event, :final move, :final includeCaptures) =>
        applyMoveToPresented(snapshot, event, move, includeCaptures: includeCaptures),
      LudoCaptureScene(:final capturedTokenIds) => applyCapturesToPresented(snapshot, capturedTokenIds),
      LudoFinishScene() => snapshot, // the move already landed the token
      _ => reduceLudoEvent(snapshot, scene.event, scene.event.version ?? snapshot.game.version),
    };

final ludoTimelineProvider = NotifierProvider<LudoTimelineController, LudoTimelineState>(LudoTimelineController.new);
