import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../models/user.dart';
import '../../../providers/core_providers.dart';
import '../../../services/encryption_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/socket_service.dart';
import '../../profile/data/profile_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../data/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/session_state.dart';

/// Single source of truth for "is anyone logged in, and who". Restores a
/// persisted session on startup, and is what the router watches to decide
/// between the login flow and the authenticated app. Also owns the
/// realtime connection's lifecycle: connected alongside every transition
/// into `authenticated`, disconnected alongside every transition out of
/// it — so a feature widget never has to think about when the socket
/// should be up. It also owns making sure this device has an
/// end-to-end-encryption identity keypair the moment a session becomes
/// authenticated — the same "happens automatically, nobody else has to
/// think about it" shape as the socket connection.
class SessionController extends StateNotifier<SessionState> {
  SessionController(
    this._repository,
    this._secureStorage,
    this._socketService,
    this._encryptionService,
    this._profileRepository,
    this._pushNotificationService,
  ) : super(SessionState.unknown) {
    // Lives for the whole app process, same as this controller — a
    // rotated token needs re-registering whenever it happens, not just
    // at the moments `login`/`_restore` already cover.
    _tokenRefreshSubscription = _pushNotificationService.onTokenRefresh.listen(
      _onTokenRefresh,
    );
    _restore();
  }

  final AuthRepository _repository;
  final SecureStorageService _secureStorage;
  final SocketService _socketService;
  final EncryptionService _encryptionService;
  final ProfileRepository _profileRepository;
  final PushNotificationService _pushNotificationService;
  late final StreamSubscription<String> _tokenRefreshSubscription;

  Future<void> _restore() async {
    final accessToken = await _secureStorage.readAccessToken();
    if (accessToken == null) {
      state = SessionState.unauthenticated;
      return;
    }
    try {
      final user = await _repository.fetchCurrentUser();
      state = SessionState.authenticated(user);
      _socketService.connect(accessToken);
      unawaited(_ensureIdentityKeyPair(user.publicKey));
      unawaited(_ensurePushNotificationsRegistered());
    } on ApiException catch (e) {
      if (_isConnectivityFailure(e)) {
        // Couldn't even reach the backend to ask whether this token is
        // still good — leave the tokens alone (they may well still be
        // valid) and land on a retryable "can't reach the server" state
        // instead of a silent, unexplained logout. See
        // `SessionStatus.restoreFailed`'s doc comment.
        state = SessionState.restoreFailed(e.message);
        return;
      }
      // A definitive rejection (expired/invalid token, and the
      // interceptor's own transparent refresh attempt also failed) — no
      // usable session, so there's nothing lost by clearing it.
      await _secureStorage.clearTokens();
      state = SessionState.unauthenticated;
    } catch (_) {
      // Anything other than the typed ApiException above (shouldn't
      // normally happen — AuthRepository always throws that — but
      // failing safe here matters more than being right about why).
      await _secureStorage.clearTokens();
      state = SessionState.unauthenticated;
    }
  }

  /// True for the flavor of [ApiException] that means "the request never
  /// actually reached the backend and got a real answer" — no network,
  /// the server unreachable/down, a timeout, or the server up but
  /// erroring (a 5xx, e.g. the database being unavailable — see
  /// backend/src/middleware/errorHandler.js) — as opposed to the backend
  /// actively, successfully telling us the token is invalid. Only the
  /// latter is a real "you are logged out".
  bool _isConnectivityFailure(ApiException e) {
    if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') return true;
    final status = e.statusCode;
    return status != null && status >= 500;
  }

  /// Retries [_restore] after landing on [SessionStatus.restoreFailed] —
  /// wired to that state's "Retry" button (see `SplashScreen`). Resets
  /// to [SessionState.unknown] first so the UI shows the same plain
  /// loading state a fresh app launch would, rather than the error
  /// state flickering directly into itself if this retry fails again
  /// too.
  Future<void> retryRestore() {
    state = SessionState.unknown;
    return _restore();
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _repository.login(email: email, password: password);
    await _secureStorage.writeAccessToken(result.accessToken);
    await _secureStorage.writeRefreshToken(result.refreshToken);
    state = SessionState.authenticated(result.user);
    _socketService.connect(result.accessToken);
    unawaited(_ensureIdentityKeyPair(result.user.publicKey));
    unawaited(_ensurePushNotificationsRegistered());
  }

  /// Generates this device's long-term identity keypair the first time it
  /// doesn't already have one stored, and (re-)registers the public half
  /// with the backend whenever the server doesn't have one on file yet —
  /// [serverPublicKey] is the caller's already-fetched
  /// `User.publicKey`, straight off the same `login`/`fetchCurrentUser`
  /// response that triggered this call, so checking it costs no extra
  /// round trip. That server-side check matters even when a local seed
  /// already exists: the seed is written to storage *before* the
  /// `updatePublicKey` network call is attempted, so a registration that
  /// fails (offline, server error, killed mid-request) still leaves a
  /// local key behind with nothing server-side to show for it — and
  /// without re-checking [serverPublicKey] on every subsequent
  /// login/restore, that account would silently and permanently be
  /// unable to derive chat keys with anyone, with no error surfaced
  /// anywhere and no way to recover short of clearing local storage.
  /// Deliberately fire-and-forget from the caller's point of view (not
  /// awaited by [login]/[_restore]) — login shouldn't block on this, and
  /// every chat screen already degrades gracefully (see
  /// `ChatDetailController`) if a key isn't registered yet by the time
  /// the user opens a thread; it'll be there moments later.
  Future<void> _ensureIdentityKeyPair(String? serverPublicKey) async {
    final existingSeed = await _secureStorage.readIdentityPrivateKey();
    final SimpleKeyPair keyPair;
    if (existingSeed != null) {
      if (serverPublicKey != null) return; // already registered
      keyPair = await _encryptionService.keyPairFromSeed(
        base64Decode(existingSeed),
      );
    } else {
      keyPair = await _encryptionService.generateIdentityKeyPair();
      final seed = await _encryptionService.extractSeed(keyPair);
      // Stored *before* attempting to register it with the backend — if
      // registration fails, the key still exists locally next time, so
      // this branch won't regenerate a different one (which would orphan
      // anything already encrypted for the first) — the `serverPublicKey
      // != null` check above is what retries the still-unregistered
      // upload on a later login/restore instead.
      await _secureStorage.writeIdentityPrivateKey(base64Encode(seed));
    }
    final publicKey = await _encryptionService.exportPublicKey(keyPair);
    try {
      await _profileRepository.updatePublicKey(publicKey);
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }

  /// Requests notification permission and registers this device's FCM
  /// token, unless the user has previously turned notifications off via
  /// the profile screen's toggle (see
  /// `SecureStorageService.readNotificationsEnabled`) — a fresh
  /// login/restore must respect that choice, not silently re-enable
  /// what was explicitly disabled. Fire-and-forget for the same reason
  /// as [_ensureIdentityKeyPair]: this is an enhancement, never a
  /// precondition for using the app, and every step here already
  /// degrades to a no-op if Firebase isn't configured at all (see
  /// `PushNotificationService`).
  Future<void> _ensurePushNotificationsRegistered() async {
    final enabled = await _secureStorage.readNotificationsEnabled();
    if (!enabled) return;
    try {
      final token = await _pushNotificationService
          .requestPermissionAndGetToken();
      if (token == null) return; // denied, or Firebase not configured
      await _profileRepository.registerPushToken(token);
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    if (!state.isAuthenticated) return;
    try {
      await _profileRepository.registerPushToken(token);
    } catch (_) {
      // Best-effort — a missed re-registration just means this device
      // stops getting pushes until the next successful one; nothing
      // else in the app depends on it.
    }
  }

  Future<void> logout() async {
    final refreshToken = await _secureStorage.readRefreshToken();
    if (refreshToken != null) {
      // Best-effort: even if this call fails (e.g. offline), the local
      // session is cleared below so the user is logged out on-device
      // regardless.
      try {
        await _repository.logout(refreshToken: refreshToken);
      } catch (_) {
        // Intentionally ignored — see comment above.
      }
    }
    // Best-effort, same posture as the backend logout call above — a
    // signed-out device shouldn't keep receiving this user's pushes, but
    // failing to unregister (offline, Firebase unconfigured) must never
    // block actually logging out.
    try {
      final token = await _pushNotificationService.getCurrentToken();
      if (token != null) {
        await _profileRepository.unregisterPushToken(token);
      }
    } catch (_) {
      // Intentionally ignored — see comment above.
    }
    await _secureStorage.clearTokens();
    state = SessionState.unauthenticated;
    _socketService.disconnect();
  }

  /// Replaces the current user's data in-place (e.g. after verifying the
  /// email, or editing the profile) without a full login round trip.
  /// No-ops if called while not authenticated.
  void updateUser(User user) {
    if (!state.isAuthenticated) return;
    state = SessionState.authenticated(user);
  }

  /// Set the moment [forceLogoutLocally] runs, and cleared by whoever
  /// reads it via [consumeSessionExpiredFlag] — lets the login screen
  /// explain *why* the user landed back there instead of the redirect
  /// just silently dropping them at an empty form (an expired session
  /// is still an error the user needs telling about, even though there's
  /// nothing to retry). `false` after a normal, user-initiated [logout].
  bool _sessionExpired = false;

  /// Read-and-clear: true if the current `unauthenticated` state was
  /// reached because a session expired rather than because the user
  /// logged out. Cleared on read so it's only ever reported once, even
  /// if the login screen rebuilds multiple times before a new login.
  bool consumeSessionExpiredFlag() {
    final value = _sessionExpired;
    _sessionExpired = false;
    return value;
  }

  /// Called by [ApiClient.onSessionExpired] when a background request's
  /// silent token refresh fails — no server round trip here, just drop
  /// local state so the router sends the user to /login.
  Future<void> forceLogoutLocally() async {
    await _secureStorage.clearTokens();
    _sessionExpired = true;
    state = SessionState.unauthenticated;
    _socketService.disconnect();
  }

  @override
  void dispose() {
    _tokenRefreshSubscription.cancel();
    super.dispose();
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      final controller = SessionController(
        ref.watch(authRepositoryProvider),
        ref.watch(secureStorageServiceProvider),
        ref.watch(socketServiceProvider),
        ref.watch(encryptionServiceProvider),
        ref.watch(profileRepositoryProvider),
        ref.watch(pushNotificationServiceProvider),
      );
      ref.watch(apiClientProvider).onSessionExpired =
          controller.forceLogoutLocally;
      return controller;
    });
