import 'dart:async';

import 'package:dio/dio.dart';

import '../config/env.dart';
import 'secure_storage_service.dart';

/// The one [Dio] instance the whole app shares. Wraps base URL + JSON
/// headers + auth-token attachment in one place so feature repositories
/// only ever describe *what* request to make, not how to authenticate it.
///
/// Also transparently handles access-token expiry: on a 401 (from any
/// endpoint except the auth endpoints themselves), it uses the stored
/// refresh token to get a new access token and retries the original
/// request once. If refreshing fails, [onSessionExpired] is invoked so
/// the app can drop the user back to the login screen — see
/// `SessionController` for the other end of that callback.
class ApiClient {
  ApiClient({SecureStorageService? secureStorage})
    : _secureStorage = secureStorage ?? SecureStorageService(),
      dio = Dio(
        BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        ),
      ),
      // Separate instance with no interceptors, used only for the
      // refresh call itself — reusing `dio` here would re-enter this
      // same onError handler on a failed refresh.
      _refreshDio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final path = error.requestOptions.path;
          final isAuthEndpoint = path.startsWith('/auth/');
          final alreadyRetried = error.requestOptions.extra['retried'] == true;

          if (error.response?.statusCode == 401 &&
              !isAuthEndpoint &&
              !alreadyRetried) {
            final refreshed = await _refreshAccessToken();
            if (refreshed) {
              final newToken = await _secureStorage.readAccessToken();
              final retryOptions = error.requestOptions
                ..extra['retried'] = true
                ..headers['Authorization'] = 'Bearer $newToken';
              try {
                final response = await dio.fetch(retryOptions);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            } else {
              onSessionExpired?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final Dio _refreshDio;
  final SecureStorageService _secureStorage;

  /// Called when the refresh token is missing/invalid/expired and the
  /// session can no longer be renewed. Set by the provider that wires
  /// this client to `SessionController`.
  void Function()? onSessionExpired;

  // Concurrent 401s must not each try to refresh independently — the
  // refresh token is single-use (rotated server-side), so a second
  // concurrent attempt would fail after the first one succeeds. This
  // lets every caller await the same in-flight refresh instead.
  Completer<bool>? _refreshCompleter;

  Future<bool> _refreshAccessToken() {
    final inFlight = _refreshCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    () async {
      try {
        final refreshToken = await _secureStorage.readRefreshToken();
        if (refreshToken == null) {
          completer.complete(false);
          return;
        }
        final response = await _refreshDio.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );
        await _secureStorage.writeAccessToken(
          response.data['accessToken'] as String,
        );
        await _secureStorage.writeRefreshToken(
          response.data['refreshToken'] as String,
        );
        completer.complete(true);
      } catch (_) {
        await _secureStorage.clearTokens();
        completer.complete(false);
      } finally {
        _refreshCompleter = null;
      }
    }();

    return completer.future;
  }
}
