import 'package:friends_game_app/features/auth/domain/user.dart';

class AuthSession {
  const AuthSession({required this.user, required this.accessToken, required this.refreshToken});

  final User user;
  final String accessToken;
  final String refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
        accessToken: json['accessToken'].toString(),
        refreshToken: json['refreshToken'].toString(),
      );
}
