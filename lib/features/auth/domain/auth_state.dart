import 'package:friends_game_app/features/auth/domain/user.dart';

enum AuthStatus { initializing, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.user, this.loading = false, this.error});

  final AuthStatus status;
  final User? user;
  final bool loading;
  final String? error;

  AuthState copyWith({AuthStatus? status, User? user, bool? loading, String? error, bool clearError = false}) {
    return AuthState(status: status ?? this.status, user: user ?? this.user, loading: loading ?? this.loading, error: clearError ? null : (error ?? this.error));
  }
}
