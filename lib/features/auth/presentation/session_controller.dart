import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../models/user.dart';
import '../../../providers/core_providers.dart';
import '../../../services/encryption_service.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/socket_service.dart';
import '../../profile/data/profile_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../data/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/session_state.dart';

/// Single source of truth for "is anyone logged in, and who". Restores
/// a persisted session on startup. Also owns the realtime connection's
/// lifecycle and this device's end-to-end-encryption identity keypair.
class SessionController extends StateNotifier<SessionState> {
  SessionController(
    this._repository,
    this._secureStorage,
    this._socketService,
    this._encryptionService,
    this._profileRepository,
  ) : super(SessionState.unknown) {
    _restore();
  }

  final AuthRepository _repository;
  final SecureStorageService _secureStorage;
  final SocketService _socketService;
  final EncryptionService _encryptionService;
  final ProfileRepository _profileRepository;

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
    } on ApiException catch (e) {
      if (_isConnectivityFailure(e)) {
        // Couldn't reach the backend — leave tokens alone and land on a
        // retryable state instead of a silent logout.
        state = SessionState.restoreFailed(e.message);
        return;
      }
      // A definitive rejection — no usable session.
      await _secureStorage.clearTokens();
      state = SessionState.unauthenticated;
    } catch (_) {
      // Shouldn't happen, but fail safe.
      await _secureStorage.clearTokens();
      state = SessionState.unauthenticated;
    }
  }

  /// True when the request never got a real answer (no network,
  /// timeout, 5xx) — as opposed to the backend actively rejecting the
  /// token. Only the latter is a real logout.
  bool _isConnectivityFailure(ApiException e) {
    if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') return true;
    final status = e.statusCode;
    return status != null && status >= 500;
  }

  /// Retries [_restore] from [SessionStatus.restoreFailed]'s Retry
  /// button.
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
  }

  /// Generates this device's identity keypair if it doesn't have one
  /// yet, and (re-)registers the public half whenever the server
  /// doesn't have one on file — covers a registration that failed
  /// partway through on an earlier login. Fire-and-forget: login
  /// shouldn't block on this, and chats degrade gracefully until it's
  /// done.
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
      // Stored before registering — a failed upload still has a local
      // key to retry with next time, instead of regenerating a new one.
      await _secureStorage.writeIdentityPrivateKey(base64Encode(seed));
    }
    final publicKey = await _encryptionService.exportPublicKey(keyPair);
    try {
      await _profileRepository.updatePublicKey(publicKey);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> logout() async {
    final refreshToken = await _secureStorage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _repository.logout(refreshToken: refreshToken);
      } catch (_) {
        // Best-effort — local session is cleared below regardless.
      }
    }
    await _secureStorage.clearTokens();
    state = SessionState.unauthenticated;
    _socketService.disconnect();
  }

  /// Replaces the current user in place (e.g. after verifying email or
  /// editing the profile), without a full login round trip.
  void updateUser(User user) {
    if (!state.isAuthenticated) return;
    state = SessionState.authenticated(user);
  }

  /// Set by [forceLogoutLocally], cleared by [consumeSessionExpiredFlag]
  /// — lets the login screen explain why it landed there.
  bool _sessionExpired = false;

  /// Read-and-clear: true if `unauthenticated` was reached because the
  /// session expired, not because the user logged out.
  bool consumeSessionExpiredFlag() {
    final value = _sessionExpired;
    _sessionExpired = false;
    return value;
  }

  /// Called by [ApiClient.onSessionExpired] when a background token
  /// refresh fails — drops local state so the router sends to /login.
  Future<void> forceLogoutLocally() async {
    await _secureStorage.clearTokens();
    _sessionExpired = true;
    state = SessionState.unauthenticated;
    _socketService.disconnect();
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
      );
      ref.watch(apiClientProvider).onSessionExpired =
          controller.forceLogoutLocally;
      return controller;
    });
