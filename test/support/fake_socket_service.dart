import 'dart:async';

import 'package:mobile_messenger/services/socket_service.dart';

/// No-op stand-in for [SocketService], for widget tests.
///
/// `SessionController` connects the real socket once its state becomes
/// `authenticated` — real `connect()` tries an actual WebSocket
/// handshake, unmocked and unresolved in a widget test. Override
/// `socketServiceProvider` with this in any test that reaches an
/// authenticated session.
///
/// Defaults to `connected: true`, since most tests aren't exercising
/// connectivity loss. Pass `connected: false`, or call [setConnected]
/// mid-test, for tests that specifically cover the banner.
class FakeSocketService extends SocketService {
  // Not an initializing formal — that would make the external
  // parameter name `_connected` too, which other files can't spell.
  // ignore: prefer_initializing_formals
  FakeSocketService({bool connected = true}) : _connected = connected;

  bool _connected;
  final _statusController = StreamController<bool>.broadcast();

  @override
  bool get isConnected => _connected;

  @override
  Stream<bool> get connectionStatusStream => _statusController.stream;

  /// Test-only hook to simulate a connectivity change without a real
  /// socket.
  void setConnected(bool connected) {
    _connected = connected;
    _statusController.add(connected);
  }

  @override
  void connect(String accessToken) {}

  @override
  void disconnect() {}
}
