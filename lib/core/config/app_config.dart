class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.socketBaseUrl,
  });

  final String environment;
  final String apiBaseUrl;
  final String socketBaseUrl;

  static const development = AppConfig(
    environment: 'development',
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5000/api',
    ),
    socketBaseUrl: String.fromEnvironment(
      'SOCKET_BASE_URL',
      defaultValue: 'http://10.0.2.2:5000',
    ),
  );
}
