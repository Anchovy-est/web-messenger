import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin, typed wrapper around [FlutterSecureStorage] — the rest of the
/// app never touches raw string keys.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  // This device's X25519 identity private key seed — must never leave
  // the device.
  static const _identityPrivateKeyKey = 'encryption_identity_private_key';
  static const _themeOptionKey = 'app_theme_option';

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<String?> readIdentityPrivateKey() =>
      _storage.read(key: _identityPrivateKeyKey);

  Future<void> writeIdentityPrivateKey(String base64Seed) =>
      _storage.write(key: _identityPrivateKeyKey, value: base64Seed);

  /// The stored theme option name, or null if never explicitly chosen.
  Future<String?> readThemeOption() => _storage.read(key: _themeOptionKey);

  Future<void> writeThemeOption(String option) =>
      _storage.write(key: _themeOptionKey, value: option);

  /// Clears both tokens on logout. Keeps the identity key — logging
  /// back in as the same user should still decrypt past messages.
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
