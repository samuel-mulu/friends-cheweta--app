import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/storage/secure_storage.dart';
import 'package:friends_game_app/features/auth/data/auth_repository.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restoreSession);
    return const AuthState(status: AuthStatus.initializing);
  }

  Future<void> _restoreSession() async {
    final refresh = await ref.read(secureStorageProvider).readRefreshToken();
    if (refresh == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      await ref.read(secureStorageProvider).clearTokens();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({required String phoneNumber, required String password}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final session = await ref.read(authRepositoryProvider).login(phoneNumber: phoneNumber, password: password);
      await ref.read(secureStorageProvider).saveTokens(accessToken: session.accessToken, refreshToken: session.refreshToken);
      state = AuthState(status: AuthStatus.authenticated, user: session.user);
      return true;
    } on AppFailure catch (failure) {
      state = AuthState(status: AuthStatus.unauthenticated, loading: false, error: failure.message);
      return false;
    }
  }

  Future<bool> register({required String fullName, required String phoneNumber, required String password}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final session = await ref.read(authRepositoryProvider).register(fullName: fullName, phoneNumber: phoneNumber, password: password);
      await ref.read(secureStorageProvider).saveTokens(accessToken: session.accessToken, refreshToken: session.refreshToken);
      state = AuthState(status: AuthStatus.authenticated, user: session.user);
      return true;
    } on AppFailure catch (failure) {
      state = AuthState(status: AuthStatus.unauthenticated, loading: false, error: failure.message);
      return false;
    }
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    final refresh = await storage.readRefreshToken();
    if (refresh != null) await ref.read(authRepositoryProvider).logout(refresh);
    await storage.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
