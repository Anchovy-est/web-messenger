import 'dart:async';

import 'package:dio/dio.dart';

import '../config/env.dart';
import 'secure_storage_service.dart';

/// The one [Dio] instance the app shares — base URL, auth headers, and
/// transparent token refresh on a 401 (retries the request once; on
/// failure calls [onSessionExpired]).
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
      // No interceptors — avoids re-entering onError on a failed refresh.
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

  /// Called when the refresh token is missing/invalid and the session
  /// can't be renewed. Wired to `SessionController`.
  void Function()? onSessionExpired;

  // Lets concurrent 401s share one in-flight refresh instead of racing.
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
