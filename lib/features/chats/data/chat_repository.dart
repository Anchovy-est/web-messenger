import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/chat.dart';
import '../../../services/api_client.dart';

class ChatRepository {
  ChatRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Chat>> listChats({required bool archived}) async {
    try {
      final response = await _apiClient.dio.get(
        '/chats',
        queryParameters: {'archived': archived.toString()},
      );
      final chats = response.data['chats'] as List;
      return chats.cast<Map<String, dynamic>>().map(Chat.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Chat> getChat(String chatId) async {
    try {
      final response = await _apiClient.dio.get('/chats/$chatId');
      return Chat.fromJson(response.data['chat'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Chat> archive(String chatId) => _post(chatId, 'archive');

  Future<Chat> unarchive(String chatId) => _post(chatId, 'unarchive');

  /// Mutes push notifications for this chat, for the current user only.
  Future<Chat> mute(String chatId) => _post(chatId, 'mute');

  Future<Chat> unmute(String chatId) => _post(chatId, 'unmute');

  Future<Chat> _post(String chatId, String action) async {
    try {
      final response = await _apiClient.dio.post('/chats/$chatId/$action');
      return Chat.fromJson(response.data['chat'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
