import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/storage/secure_storage.dart';
import 'package:friends_game_app/features/auth/data/auth_repository.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';
import 'package:friends_game_app/features/auth/domain/user.dart';

/// Session lifecycle. Start-up never waits on the network when it does not
/// have to:
/// - no saved session → sign-in screen at once;
/// - saved session + cached profile → straight in; the server confirms in the
///   background and only a rejected session signs the user out;
/// - saved session, no cached profile (first start after an update) → ask the
///   server, but at most [restoreTimeout]; then offer Retry on the splash.
class AuthController extends Notifier<AuthState> {
  static const restoreTimeout = Duration(seconds: 12);

  @override
  AuthState build() {
    Future.microtask(restoreSession);
    return const AuthState(status: AuthStatus.initializing);
  }

  SecureStorage get _storage => ref.read(secureStorageProvider);

  Future<void> restoreSession() async {
    state = const AuthState(status: AuthStatus.initializing, loading: true);
    final refresh = await _storage.readRefreshToken();
    if (refresh == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    final cached = _storage.readCachedUser();
    if (cached != null) {
      state = AuthState(status: AuthStatus.authenticated, user: User.fromJson(cached));
      unawaited(_confirmWithServer());
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).me().timeout(restoreTimeout);
      await _signedIn(user);
    } on AppFailure catch (failure) {
      if (_sessionRejected(failure)) return _signOutLocally(failure.message);
      state = AuthState(status: AuthStatus.initializing, error: _offlineMessage);
    } on TimeoutException {
      state = AuthState(status: AuthStatus.initializing, error: _offlineMessage);
    } catch (_) {
      state = AuthState(status: AuthStatus.initializing, error: _offlineMessage);
    }
  }

  static const _offlineMessage = 'We can\'t reach Friends right now. Check your connection and try again.';

  /// Background check of a session restored from cache.
  Future<void> _confirmWithServer() async {
    try {
      final user = await ref.read(authRepositoryProvider).me();
      if (state.status == AuthStatus.authenticated) await _signedIn(user);
    } on AppFailure catch (failure) {
      if (_sessionRejected(failure) && state.status == AuthStatus.authenticated) {
        await _signOutLocally('Your session has ended. Please sign in again.');
      }
    } catch (_) {
      // Offline or server asleep: keep the session; screens retry on their own.
    }
  }

  bool _sessionRejected(AppFailure failure) =>
      failure.kind == FailureKind.unauthorized || failure.isAccountBlocked;

  Future<void> _signOutLocally(String message) async {
    await _storage.clearTokens();
    state = AuthState(status: AuthStatus.unauthenticated, error: message);
  }

  Future<void> _signedIn(User user) async {
    await _storage.cacheUser(user.toJson());
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<bool> login({required String phoneNumber, required String password}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final session = await ref.read(authRepositoryProvider).login(phoneNumber: phoneNumber, password: password);
      await _storage.saveTokens(accessToken: session.accessToken, refreshToken: session.refreshToken);
      await _signedIn(session.user);
      return true;
    } on AppFailure catch (failure) {
      state = AuthState(status: AuthStatus.unauthenticated, loading: false, error: failure.message);
      return false;
    }
  }

  Future<bool> register({required String fullName, required String phoneNumber, required String password, required String otp}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final session = await ref.read(authRepositoryProvider).register(fullName: fullName, phoneNumber: phoneNumber, password: password, otp: otp);
      await _storage.saveTokens(accessToken: session.accessToken, refreshToken: session.refreshToken);
      await _signedIn(session.user);
      return true;
    } on AppFailure catch (failure) {
      state = AuthState(status: AuthStatus.unauthenticated, loading: false, error: failure.message);
      return false;
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await ref.read(authRepositoryProvider).changePassword(currentPassword, newPassword);
    await _signOutLocally('Password changed. Sign in with your new password.');
  }

  Future<void> logout() async {
    final refresh = await _storage.readRefreshToken();
    // Best effort: signing out on this phone must work offline too.
    if (refresh != null) {
      try {
        await ref.read(authRepositoryProvider).logout(refresh).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _storage.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
