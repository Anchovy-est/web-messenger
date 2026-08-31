import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/user.dart';
import '../../../services/api_client.dart';

class ProfileRepository {
  ProfileRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<User> fetchProfile() async {
    try {
      final response = await _apiClient.dio.get('/users/me');
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> updateProfile({
    required String username,
    required String bio,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        '/users/me',
        data: {'username': username, 'bio': bio},
      );
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Registers/replaces this device's end-to-end encryption public key.
  /// The private key never goes anywhere near this call.
  Future<User> updatePublicKey(String publicKey) async {
    try {
      final response = await _apiClient.dio.put(
        '/users/me/public-key',
        data: {'publicKey': publicKey},
      );
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Registers this device's push token with the backend.
  Future<void> registerPushToken(
    String token, {
    String platform = 'android',
  }) async {
    try {
      await _apiClient.dio.put(
        '/users/me/push-token',
        data: {'token': token, 'platform': platform},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Unregisters this device's push token — on logout, or when the
  /// in-app toggle is turned off.
  Future<void> unregisterPushToken(String token) async {
    try {
      await _apiClient.dio.delete(
        '/users/me/push-token',
        data: {'token': token},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Bytes + filename, not a file path — works on Web too, where a
  /// picked file has no real path. The backend re-validates the file
  /// type by magic bytes either way.
  Future<User> uploadAvatar({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final formData = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _apiClient.dio.post(
        '/users/me/avatar',
        data: formData,
      );
      return User.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
