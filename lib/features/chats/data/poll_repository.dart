import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/message.dart';
import '../../../models/poll.dart';
import '../../../services/api_client.dart';

/// Talks to `/chats/:id/polls`. Unlike message bodies, a poll's
/// question/options aren't end-to-end encrypted — see [Poll].
class PollRepository {
  PollRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Creates a poll in a group chat — comes back as a new [Message]
  /// with [Message.poll] already attached.
  Future<Message> createPoll(
    String chatId, {
    required String question,
    required List<String> options,
    required bool isAnonymous,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/chats/$chatId/polls',
        data: {
          'question': question,
          'options': options,
          'isAnonymous': isAnonymous,
        },
      );
      final message = Message.fromJson(
        response.data['message'] as Map<String, dynamic>,
      );
      final poll = Poll.fromJson(response.data['poll'] as Map<String, dynamic>);
      return message.copyWith(poll: poll);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Casts a first vote, or changes an existing one — the backend
  /// treats both the same way.
  Future<Poll> vote(String chatId, String pollId, String optionId) async {
    try {
      final response = await _apiClient.dio.post(
        '/chats/$chatId/polls/$pollId/vote',
        data: {'optionId': optionId},
      );
      return Poll.fromJson(response.data['poll'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Retracts this user's own vote — idempotent server-side (retracting
  /// when there's nothing to retract just returns the poll unchanged,
  /// not an error).
  Future<Poll> retractVote(String chatId, String pollId) async {
    try {
      final response = await _apiClient.dio.delete(
        '/chats/$chatId/polls/$pollId/vote',
      );
      return Poll.fromJson(response.data['poll'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
