import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/user.dart';
import '../../../services/api_client.dart';
import 'login_result.dart';

/// Everything the auth feature needs from the backend — typed methods
/// that throw [ApiException] on failure.
class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<User> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return LoginResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> logout({required String refreshToken}) async {
    try {
      await _apiClient.dio.post(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Used at startup to check whether a persisted session is still
  /// valid.
  Future<User> fetchCurrentUser() async {
    try {
      final response = await _apiClient.dio.get('/auth/me');
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> verifyEmail({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/verify-email',
        data: {'email': email, 'code': code},
      );
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> resendVerification({required String email}) async {
    try {
      await _apiClient.dio.post(
        '/auth/resend-verification',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> forgotPassword({required String email}) async {
    try {
      await _apiClient.dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      await _apiClient.dio.post(
        '/auth/reset-password',
        data: {'email': email, 'code': code, 'newPassword': newPassword},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
