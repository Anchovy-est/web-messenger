import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import '../../../models/invitation.dart';
import '../../../services/api_client.dart';

class InvitationRepository {
  InvitationRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Throws [ApiException] with code `ALREADY_IN_CHAT` (details:
  /// `{chatId}`) if the two users already share a chat, or
  /// `INVITATION_ALREADY_PENDING` (details: `{invitationId}`) if one is
  /// already outstanding between them — see backend/src/services/
  /// invitation.service.js. Both carry enough in `details` for the UI to
  /// route straight to the relevant chat/invitation instead of just
  /// showing an error.
  Future<Invitation> sendInvitation(String inviteeId) async {
    try {
      final response = await _apiClient.dio.post(
        '/invitations',
        data: {'inviteeId': inviteeId},
      );
      return Invitation.fromJson(
        response.data['invitation'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Invitation>> listReceived({InvitationStatus? status}) async {
    return _list('/invitations/received', status);
  }

  Future<List<Invitation>> listSent({InvitationStatus? status}) async {
    return _list('/invitations/sent', status);
  }

  Future<List<Invitation>> _list(String path, InvitationStatus? status) async {
    try {
      final response = await _apiClient.dio.get(
        path,
        queryParameters: status == null ? null : {'status': status.name},
      );
      final invitations = response.data['invitations'] as List;
      return invitations
          .cast<Map<String, dynamic>>()
          .map(Invitation.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Invitation> accept(String invitationId) =>
      _respond(invitationId, 'accept');

  Future<Invitation> decline(String invitationId) =>
      _respond(invitationId, 'decline');

  Future<Invitation> _respond(String invitationId, String action) async {
    try {
      final response = await _apiClient.dio.post(
        '/invitations/$invitationId/$action',
      );
      return Invitation.fromJson(
        response.data['invitation'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
