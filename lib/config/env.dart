/// Build-time configuration for reaching the backend.
///
/// Override at build/run time with `--dart-define`, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3001
///
/// Defaults target the Android emulator's alias for the host machine's
/// localhost (`10.0.2.2`), matching the backend's docker-compose host port
/// (see docker-compose.yml — 3001 was chosen there to dodge a local port
/// conflict on this dev machine, not for any architectural reason).
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
