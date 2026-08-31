import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/message.dart';
import '../../../services/api_client.dart';

/// Every `body`/media payload here is an opaque end-to-end-encrypted
/// envelope — encryption/decryption happen one layer up, in
/// `ChatDetailController`. This is a dumb transport layer.
class MessageRepository {
  MessageRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Oldest-first. Without `before`, the most recent `limit` messages;
  /// with it, the `limit` messages preceding that one.
  Future<List<Message>> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/chats/$chatId/messages',
        queryParameters: {'limit': limit.toString(), 'before': ?before},
      );
      final messages = response.data['messages'] as List;
      return messages
          .cast<Map<String, dynamic>>()
          .map(Message.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [body] is expected to already be an encrypted envelope; the
  /// realtime push to other participants happens server-side after.
  Future<Message> sendMessage(String chatId, String body) async {
    try {
      final response = await _apiClient.dio.post(
        '/chats/$chatId/messages',
        data: {'body': body},
      );
      return Message.fromJson(response.data['message'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Uploads an already-compressed, already-encrypted image or video.
  /// [type] rides as a plain field since the server can't sniff an
  /// encrypted file's real type. [body] is only non-null for a group
  /// chat's media message — the wrapped one-time media key, one entry
  /// per recipient.
  Future<Message> sendMediaMessage(
    String chatId,
    Uint8List bytes,
    String type, {
    String? body,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'blob.enc'),
        'type': type,
        'body': ?body,
      });
      final response = await _apiClient.dio.post(
        '/chats/$chatId/messages/media',
        data: formData,
        // Generous timeout — a large file over a slow link needs more
        // than the default 15s.
        options: Options(sendTimeout: const Duration(seconds: 90)),
      );
      return Message.fromJson(response.data['message'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Downloads the raw, still-encrypted bytes behind a message's
  /// `mediaUrl` — decryption is the caller's job.
  Future<Uint8List> downloadMedia(String mediaUrl) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        mediaUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Acks "my device now has these messages".
  Future<void> markDelivered(String chatId) async {
    try {
      await _apiClient.dio.post('/chats/$chatId/delivered');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Acks "I've actually viewed this chat's thread".
  Future<void> markRead(String chatId) async {
    try {
      await _apiClient.dio.post('/chats/$chatId/read');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [body] is again an encrypted envelope. Backend enforces
  /// sender-only.
  Future<Message> editMessage(
    String chatId,
    String messageId,
    String body,
  ) async {
    try {
      final response = await _apiClient.dio.patch(
        '/chats/$chatId/messages/$messageId',
        data: {'body': body},
      );
      return Message.fromJson(response.data['message'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Soft-deletes a message — the backend keeps a tombstone. Same
  /// sender-only enforcement as [editMessage].
  Future<Message> deleteMessage(String chatId, String messageId) async {
    try {
      final response = await _apiClient.dio.delete(
        '/chats/$chatId/messages/$messageId',
      );
      return Message.fromJson(response.data['message'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
