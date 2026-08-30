import 'dart:async';

import 'package:mobile_messenger/services/socket_service.dart';

/// No-op stand-in for [SocketService], for widget tests.
///
/// `SessionController` connects the real socket the moment its state
/// becomes `authenticated` — real `connect()` would try an actual
/// WebSocket handshake, which is unmocked here and (like the raw
/// `flutter_secure_storage` platform channel before it) doesn't resolve
/// cleanly in the widget-test environment. Override
/// `socketServiceProvider` with this in any test that reaches an
/// authenticated session.
///
/// Defaults to reporting a live connection (`connected: true`) — most
/// tests aren't exercising connectivity loss, and a permanently-shown
/// "no connection" banner (`ConnectionBanner`) would just be noise on
/// every one of them. Pass `connected: false`, or call [setConnected]
/// mid-test, for the tests that specifically cover that banner.
class FakeSocketService extends SocketService {
  // Not an initializing formal (`this._connected`) on purpose: that
  // would make the external parameter name `_connected` too, which
  // other files (every test that constructs this) couldn't spell —
  // private identifiers aren't accessible outside their own library.
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
