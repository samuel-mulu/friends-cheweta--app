import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/auth/domain/auth_session.dart';
import 'package:friends_game_app/features/auth/domain/user.dart';

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<AuthSession> login({required String phoneNumber, required String password}) async {
    final response = await _api.request<Map<String, dynamic>>('/auth/login', method: 'POST', authenticated: false, data: {
      'phoneNumber': phoneNumber.trim(),
      'password': password,
      'deviceName': 'Flutter',
    });
    return AuthSession.fromJson(response.data!);
  }

  Future<AuthSession> register({required String fullName, required String phoneNumber, required String password}) async {
    final response = await _api.request<Map<String, dynamic>>('/auth/register', method: 'POST', authenticated: false, data: {
      'fullName': fullName.trim(),
      'phoneNumber': phoneNumber.trim(),
      'password': password,
      'deviceName': 'Flutter',
    });
    return AuthSession.fromJson(response.data!);
  }

  Future<User> me() async {
    final response = await _api.request<Map<String, dynamic>>('/users/me');
    return User.fromJson(response.data!);
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _api.request<void>('/auth/logout', method: 'POST', data: {'refreshToken': refreshToken});
    } catch (_) {
      // Local logout must still complete if server is unavailable.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)));
