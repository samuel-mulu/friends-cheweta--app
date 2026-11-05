import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';

enum LudoPresentationKind { matchStarted, dice, move, capture, finish, turn, extraRoll, matchFinished }

class LudoPresentationEvent {
  const LudoPresentationEvent({
    required this.kind,
    this.playerId,
    this.diceValue,
    this.tokenId,
    this.move,
    this.tokenIds = const [],
  });
  final LudoPresentationKind kind;
  final String? playerId;
  final int? diceValue;
  final String? tokenId;
  final LudoMoveResolution? move;
  final List<String> tokenIds;
}

class LudoAnimationState {
  const LudoAnimationState({this.current, this.pendingCount = 0, this.sequence = 0, this.blocking = false});
  final LudoPresentationEvent? current;
  final int pendingCount;
  final int sequence;

  /// A dice / move / capture / home animation is showing or queued. Input
  /// waits for these (so a token never glows before its dice lands); short
  /// notices such as "turn started" never block a tap.
  final bool blocking;
  bool get busy => current != null;
}

class LudoAnimationQueueController extends Notifier<LudoAnimationState> {
  final List<LudoPresentationEvent> _queue = [];
  bool _draining = false;
  int _sequence = 0;

  /// Bumped by [clear]; a drain loop from an older generation stops silently.
  int _generation = 0;

  static const _blockingKinds = {
    LudoPresentationKind.dice,
    LudoPresentationKind.move,
    LudoPresentationKind.capture,
    LudoPresentationKind.finish,
  };

  @override
  LudoAnimationState build() => const LudoAnimationState();

  void enqueue(LudoPresentationEvent event) {
    _queue.add(event);
    _publish(state.current, sequence: state.sequence);
    if (!_draining) unawaited(_drain(_generation));
  }

  void clear() {
    _generation++;
    _queue.clear();
    _draining = false;
    _publish(null, sequence: ++_sequence);
  }

  Future<void> _drain(int generation) async {
    _draining = true;
    while (_queue.isNotEmpty) {
      final current = _queue.removeAt(0);
      _publish(current, sequence: ++_sequence);
      await Future<void>.delayed(durationFor(current));
      if (generation != _generation) return; // cleared meanwhile; a newer loop owns the queue
    }
    _draining = false;
    _publish(null, sequence: ++_sequence);
  }

  void _publish(LudoPresentationEvent? current, {required int sequence}) {
    state = LudoAnimationState(
      current: current,
      pendingCount: _queue.length,
      sequence: sequence,
      blocking: (current != null && _blockingKinds.contains(current.kind)) ||
          _queue.any((event) => _blockingKinds.contains(event.kind)),
    );
  }

  /// How long each presented event holds the stage. Moves scale with the
  /// number of cells walked; notices are brief so the game never feels slow.
  static Duration durationFor(LudoPresentationEvent event) => switch (event.kind) {
        LudoPresentationKind.matchStarted => const Duration(milliseconds: 250),
        LudoPresentationKind.dice => LudoMotion.diceRoll,
        LudoPresentationKind.move => LudoMotion.moveDuration(event.move),
        LudoPresentationKind.capture => LudoMotion.captureFlight,
        LudoPresentationKind.finish => const Duration(milliseconds: 450),
        LudoPresentationKind.turn => const Duration(milliseconds: 120),
        LudoPresentationKind.extraRoll => const Duration(milliseconds: 150),
        LudoPresentationKind.matchFinished => const Duration(milliseconds: 900),
      };
}

final ludoAnimationQueueProvider = NotifierProvider<LudoAnimationQueueController, LudoAnimationState>(
  LudoAnimationQueueController.new,
);
