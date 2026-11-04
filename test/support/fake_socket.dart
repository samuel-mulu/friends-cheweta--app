import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';
import 'package:friends_game_app/features/auth/domain/user.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';

/// In-memory socket: records emitted commands, lets tests push server events.
class FakeSocket extends Fake implements GameSocketService {
  final events$ = StreamController<RealtimeEvent>.broadcast();
  final statuses$ = StreamController<GameSocketStatus>.broadcast();
  final sent = <String>[];
  Map<String, dynamic> Function(String event, Map<String, dynamic> payload) reply = (_, __) => {'ok': true};

  @override
  Stream<RealtimeEvent> get events => events$.stream;
  @override
  Stream<GameSocketStatus> get statuses => statuses$.stream;
  @override
  Future<Map<String, dynamic>> emitWithAck(String event, [Map<String, dynamic> payload = const {}]) async {
    sent.add(event);
    return reply(event, payload);
  }

  void push(String name, Map<String, dynamic> data) => events$.add(RealtimeEvent(name: name, payload: {'data': data}));
}

class SignedInAs extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: User(id: 'me', fullName: 'Me', phoneNumber: '0', role: 'PLAYER', status: 'ACTIVE'),
      );
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
