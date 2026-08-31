import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/encryption_service.dart';
import '../services/push_notification_service.dart';
import '../services/secure_storage_service.dart';
import '../services/socket_service.dart';

/// App-wide singletons, exposed via Riverpod so every feature reads the
/// same instances instead of constructing their own.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

// Stateless crypto operations (X25519/HKDF/AES-256-GCM); see
// encryption_service.dart. A plain singleton like the
// others here, not per-chat — chat-specific state (the derived key) is
// owned by whichever controller needs it, not by this service itself.
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(secureStorage: ref.watch(secureStorageServiceProvider));
});

// Connected/disconnected by SessionController alongside its own state
// transitions — see session_controller.dart.
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(
    secureStorage: ref.watch(secureStorageServiceProvider),
  );
  ref.onDispose(service.disconnect);
  return service;
});

/// Live view of [SocketService.isConnected], for `ConnectionBanner`.
/// Seeded with the service's current value (rather than only starting
/// from whatever the stream happens to emit next) so a screen that
/// mounts after a drop has already happened still shows the banner
/// immediately, instead of waiting for the next state change.
final socketConnectionStatusProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(socketServiceProvider);
  yield service.isConnected;
  yield* service.connectionStatusStream;
});

// A plain singleton like the others here — `initialize()` (called once,
// from `MessengerApp`) and the actual permission/token calls (driven by
// `SessionController`) are both safe no-ops if this device has no
// working Firebase configuration; see push_notification_service.dart.
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService();
  ref.onDispose(service.dispose);
  return service;
});
