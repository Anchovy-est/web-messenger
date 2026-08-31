import 'package:mobile_messenger/services/secure_storage_service.dart';

// A fixed, valid X25519 seed. Exported so a test that needs to
// independently re-derive the same chat key the controller computed —
// e.g. to decrypt a "sent" ciphertext and check the plaintext — can
// reconstruct this identity keypair via
// `EncryptionService().keyPairFromSeed(base64Decode(testIdentityPrivateKeySeed))`.
const testIdentityPrivateKeySeed =
    'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

/// In-memory stand-in for [SecureStorageService], for widget tests.
///
/// [SecureStorageService] wraps a real platform channel, unmocked in
/// the widget-test environment — calling it directly hangs/throws
/// instead of resolving. Override `secureStorageServiceProvider` with
/// this in any test that touches it, transitively via SessionController.
class FakeSecureStorageService implements SecureStorageService {
  FakeSecureStorageService({
    this.accessToken,
    this.refreshToken,
    this.identityPrivateKey = testIdentityPrivateKeySeed,
    this.notificationsEnabled = true,
    this.themeOption,
  });

  String? accessToken;
  String? refreshToken;
  String? identityPrivateKey;
  bool notificationsEnabled;
  String? themeOption;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<void> writeAccessToken(String token) async => accessToken = token;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String token) async => refreshToken = token;

  @override
  Future<String?> readIdentityPrivateKey() async => identityPrivateKey;

  @override
  Future<void> writeIdentityPrivateKey(String base64Seed) async =>
      identityPrivateKey = base64Seed;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> readNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<void> writeNotificationsEnabled(bool enabled) async =>
      notificationsEnabled = enabled;

  @override
  Future<String?> readThemeOption() async => themeOption;

  @override
  Future<void> writeThemeOption(String option) async => themeOption = option;
}
