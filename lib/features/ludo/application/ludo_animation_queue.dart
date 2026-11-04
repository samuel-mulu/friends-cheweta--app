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
  const LudoAnimationState({this.current, this.pendingCount = 0, this.sequence = 0});
  final LudoPresentationEvent? current;
  final int pendingCount;
  final int sequence;
  bool get busy => current != null;
}

class LudoAnimationQueueController extends Notifier<LudoAnimationState> {
  final List<LudoPresentationEvent> _queue = [];
  bool _draining = false;
  int _sequence = 0;

  @override
  LudoAnimationState build() => const LudoAnimationState();

  void enqueue(LudoPresentationEvent event) {
    _queue.add(event);
    state = LudoAnimationState(current: state.current, pendingCount: _queue.length, sequence: state.sequence);
    if (!_draining) unawaited(_drain());
  }

  void clear() {
    _queue.clear();
    _draining = false;
    state = LudoAnimationState(sequence: ++_sequence);
  }

  Future<void> _drain() async {
    _draining = true;
    while (_queue.isNotEmpty) {
      final current = _queue.removeAt(0);
      state = LudoAnimationState(current: current, pendingCount: _queue.length, sequence: ++_sequence);
      await Future<void>.delayed(durationFor(current));
    }
    _draining = false;
    state = LudoAnimationState(sequence: ++_sequence);
  }

  /// How long each presented event holds the stage. Moves scale with the
  /// number of cells walked so long and short moves both feel natural.
  static Duration durationFor(LudoPresentationEvent event) => switch (event.kind) {
        LudoPresentationKind.matchStarted => const Duration(milliseconds: 400),
        LudoPresentationKind.dice => LudoMotion.diceRoll,
        LudoPresentationKind.move => LudoMotion.moveDuration(event.move),
        LudoPresentationKind.capture => LudoMotion.captureFlight,
        LudoPresentationKind.finish => const Duration(milliseconds: 450),
        LudoPresentationKind.turn => const Duration(milliseconds: 260),
        LudoPresentationKind.extraRoll => const Duration(milliseconds: 300),
        LudoPresentationKind.matchFinished => const Duration(milliseconds: 900),
      };
}

final ludoAnimationQueueProvider = NotifierProvider<LudoAnimationQueueController, LudoAnimationState>(
  LudoAnimationQueueController.new,
);
