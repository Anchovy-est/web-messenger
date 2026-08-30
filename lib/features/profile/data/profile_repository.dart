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

  /// Registers/replaces this device's end-to-end encryption public key —
  /// called by [SessionController] the first time this device has no
  /// locally-stored identity keypair yet. See
  /// lib/services/encryption_service.dart; the corresponding private key
  /// never goes anywhere near this call.
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

  /// Registers this device's push notification token with the backend
  /// (see backend/src/services/push.service.js) — called by
  /// [SessionController] after login/restore, and again whenever
  /// [PushNotificationService.onTokenRefresh] fires. A device with no
  /// registered token simply never receives a push; no error to handle
  /// beyond the normal [ApiException] path.
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

  /// Unregisters this device's push token — called on logout, and by
  /// the in-app "Push notifications" toggle when turned off, so a
  /// signed-out (or opted-out) device stops receiving pushes immediately.
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

  /// [filePath] is a local file path (from image_picker). The backend is
  /// the authoritative validator of format/size (see backend/src/utils/
  /// imageType.js) — this just ships the bytes; a rejected file surfaces
  /// as a normal [ApiException] (INVALID_FILE_TYPE / FILE_TOO_LARGE) for
  /// the UI to display.
  Future<User> uploadAvatar(String filePath) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath),
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
