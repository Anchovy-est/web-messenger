import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/encryption_service.dart';
import '../services/secure_storage_service.dart';
import '../services/socket_service.dart';

/// App-wide singletons, exposed via Riverpod so every feature reads the
/// same instances instead of constructing their own.
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(secureStorage: ref.watch(secureStorageServiceProvider));
});

// Connected/disconnected by SessionController alongside its own state.
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(
    secureStorage: ref.watch(secureStorageServiceProvider),
  );
  ref.onDispose(service.disconnect);
  return service;
});

/// Live view of [SocketService.isConnected], for `ConnectionBanner`.
/// Seeded with the current value so a screen that mounts after a drop
/// still shows the banner right away.
final socketConnectionStatusProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(socketServiceProvider);
  yield service.isConnected;
  yield* service.connectionStatusStream;
});
