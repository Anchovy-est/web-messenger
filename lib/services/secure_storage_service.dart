import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin, typed wrapper around [FlutterSecureStorage] so the rest of the app
/// never touches raw string keys directly. Used for auth tokens (session
/// persistence) and anything else that must survive app restarts but
/// shouldn't live in plain SharedPreferences.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  // This device's long-term X25519 identity *private* key seed,
  // base64-encoded — the one piece of key material in
  // the whole encryption design that's genuinely sensitive and must never
  // leave the device (see lib/services/encryption_service.dart and
  // docs/ENCRYPTION.md). `flutter_secure_storage` is backed by the
  // platform Keystore/Keychain, same protection every auth token here
  // already relies on.
  static const _identityPrivateKeyKey = 'encryption_identity_private_key';
  // Whether the user has opted into push notifications, via the "Push
  // notifications" toggle on the profile screen — distinct from the OS
  // permission itself (see NotificationSettingsController): this is the
  // app remembering the user's own choice, so a fresh login/restore
  // doesn't silently re-register a token for someone who explicitly
  // turned notifications off. Absent (not just "false") means "never
  // asked" — treated as enabled by default, matching every messaging
  // app's actual default.
  static const _notificationsEnabledKey = 'notifications_enabled';
  // The user's explicitly-chosen app theme ('light' | 'dark' | 'floral')
  // — see ThemeController. Not sensitive, but reuses this service rather
  // than adding a new dependency for one more small persisted
  // preference flag, same reasoning as _notificationsEnabledKey above.
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

  /// `true` unless the user has explicitly turned notifications off —
  /// see [_notificationsEnabledKey]'s doc comment for why "never set" and
  /// "set to true" mean the same thing.
  Future<bool> readNotificationsEnabled() async {
    final value = await _storage.read(key: _notificationsEnabledKey);
    return value != 'false';
  }

  Future<void> writeNotificationsEnabled(bool enabled) =>
      _storage.write(key: _notificationsEnabledKey, value: enabled.toString());

  /// The raw stored theme option name, or `null` if the user has never
  /// explicitly picked one — see `ThemeController` for how that's
  /// resolved into an actual default.
  Future<String?> readThemeOption() => _storage.read(key: _themeOptionKey);

  Future<void> writeThemeOption(String option) =>
      _storage.write(key: _themeOptionKey, value: option);

  /// Clears both tokens — called on logout. Deliberately does *not* clear
  /// the identity private key: logging out and back in as the same user
  /// on the same device should still be able to decrypt that user's past
  /// messages, which depends on this exact key surviving the session
  /// boundary (see docs/ENCRYPTION.md).
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
