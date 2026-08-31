/// Build-time config for reaching the backend. Override with
/// `--dart-define=API_BASE_URL=...`. Defaults to the Android emulator's
/// alias for localhost.
class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: apiBaseUrl,
  );
}
