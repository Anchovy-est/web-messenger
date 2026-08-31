import 'package:equatable/equatable.dart';

/// Trimmed-down user info embedded in an invitation — no email or bio.
class InvitationParticipant extends Equatable {
  const InvitationParticipant({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory InvitationParticipant.fromJson(Map<String, dynamic> json) {
    return InvitationParticipant(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, username, displayName, avatarUrl];
}

enum InvitationStatus { pending, accepted, declined }

InvitationStatus _statusFromJson(String value) {
  return InvitationStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => InvitationStatus.pending,
  );
}

class Invitation extends Equatable {
  const Invitation({
    required this.id,
    required this.chatId,
    required this.status,
    required this.createdAt,
    required this.inviter,
    required this.invitee,
    this.respondedAt,
  });

  final String id;
  final String chatId;
  final InvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final InvitationParticipant inviter;
  final InvitationParticipant invitee;

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      status: _statusFromJson(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      respondedAt: json['respondedAt'] == null
          ? null
          : DateTime.parse(json['respondedAt'] as String),
      inviter: InvitationParticipant.fromJson(
        json['inviter'] as Map<String, dynamic>,
      ),
      invitee: InvitationParticipant.fromJson(
        json['invitee'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  List<Object?> get props => [
    id,
    chatId,
    status,
    createdAt,
    respondedAt,
    inviter,
    invitee,
  ];
}
