import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/message.dart';
import '../../../services/api_client.dart';

/// Every `body`/media byte payload that crosses this boundary is an
/// opaque end-to-end-encrypted envelope, not plaintext — encryption
/// and decryption both happen one layer up, in `ChatDetailController`
/// (which owns the chat's derived key), not here. This repository stays
/// exactly what it's always been: a dumb transport layer that doesn't
/// know or care what the bytes it's moving actually mean.
class MessageRepository {
  MessageRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Oldest-first. Without `before`, the most recent `limit` messages.
  /// With it (a message id), the `limit` messages immediately preceding
  /// that one — for loading earlier history.
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

  /// Persists the message (source of truth); the realtime push to the
  /// other participant(s) happens server-side after this succeeds — see
  /// `SocketService`. [body] is expected to already be an end-to-end
  /// encrypted envelope (see `ChatDetailController.encryptText` via
  /// `EncryptionService`) — this call has no idea whether that's true,
  /// it just ships whatever string it's given.
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

  /// Uploads an already-compressed *and already end-to-end-encrypted*
  /// image or video — [bytes] is ciphertext produced by
  /// `EncryptionService.encryptBytes`, and [type]
  /// (`'image'` or `'video'`) rides alongside as a plain form field since
  /// the server can no longer sniff a real media type from encrypted
  /// bytes (see backend/src/services/message.service.js
  /// `sendMediaMessage`). The server independently re-enforces the 20MB
  /// cap (backend/src/middleware/upload.js) regardless of whether
  /// client-side compression already got under it.
  Future<Message> sendMediaMessage(
    String chatId,
    Uint8List bytes,
    String type,
  ) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'blob.enc'),
        'type': type,
      });
      final response = await _apiClient.dio.post(
        '/chats/$chatId/messages/media',
        data: formData,
        // Up to 20MB over a slow mobile upload link can easily take
        // longer than the API client's default 15s — that default is
        // sized for ordinary JSON requests, not a file body. A generous,
        // media-specific timeout means a real slow connection gets to
        // finish instead of being cut off and reported as a failure it
        // wasn't.
        options: Options(sendTimeout: const Duration(seconds: 90)),
      );
      return Message.fromJson(response.data['message'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Downloads the raw (still-encrypted) bytes behind a message's
  /// `mediaUrl` — decryption is the caller's job (`ChatDetailController`
  /// holds the chat's derived key; this repository never does). Used to
  /// render a received image/video, and my own once it's no longer just
  /// the local pre-upload file (see `_MessageBubble` in
  /// chat_detail_screen.dart).
  Future<Uint8List> downloadMedia(String mediaUrl) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        mediaUrl,
        // Same reasoning as the media upload's own timeout override
        // above — a multi-megabyte download deserves more than the
        // default JSON-sized 15s.
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

  /// Acks "my device now has these messages" — called the moment a
  /// `message:new` push arrives for any chat (see
  /// `message_delivery_ack_provider.dart`), regardless of whether that
  /// chat's thread is open. Errors are the caller's problem to decide how
  /// to handle; this method doesn't swallow them.
  Future<void> markDelivered(String chatId) async {
    try {
      await _apiClient.dio.post('/chats/$chatId/delivered');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Acks "I've actually viewed this chat's thread" — called by
  /// [ChatDetailController] once its history load succeeds.
  Future<void> markRead(String chatId) async {
    try {
      await _apiClient.dio.post('/chats/$chatId/read');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Edits a message's content — [body] is, again, expected to already
  /// be an encrypted envelope. The backend enforces that only the
  /// original sender may do this (see backend/src/services/
  /// message.service.js `editMessage`) — a 403 here means the UI let a
  /// request through it shouldn't have, not a normal failure to handle
  /// quietly, since the edit affordance is only ever shown on your own
  /// messages in the first place.
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

  /// Deletes (soft — the backend keeps a tombstone) a message. Same
  /// sender-only enforcement as [editMessage], for the same reason: the
  /// delete affordance only ever appears on my own messages, so a
  /// rejection here means something's wrong, not something to handle
  /// quietly.
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
