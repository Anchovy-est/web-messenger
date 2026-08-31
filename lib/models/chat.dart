import 'package:equatable/equatable.dart';

/// The other 1:1 participant in a chat.
class ChatParticipant extends Equatable {
  const ChatParticipant({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.publicKey,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  /// This participant's end-to-end encryption public key. Null until
  /// they've registered one.
  final String? publicKey;

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      publicKey: json['publicKey'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, username, displayName, avatarUrl, publicKey];
}

class LastMessagePreview extends Equatable {
  const LastMessagePreview({
    required this.id,
    required this.type,
    required this.senderId,
    required this.createdAt,
    this.body,
  });

  final String id;
  final String type;
  final String? body;
  final String senderId;
  final DateTime createdAt;

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) {
    return LastMessagePreview(
      id: json['id'] as String,
      type: json['type'] as String,
      body: json['body'] as String?,
      senderId: json['senderId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// [body] overrides the stored value when given — used to swap in the
  /// decrypted plaintext.
  LastMessagePreview copyWith({String? body}) {
    return LastMessagePreview(
      id: id,
      type: type,
      body: body ?? this.body,
      senderId: senderId,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id, type, body, senderId, createdAt];
}

class Chat extends Equatable {
  const Chat({
    required this.id,
    required this.isGroup,
    required this.createdAt,
    this.name,
    this.archivedAt,
    this.mutedAt,
    this.otherParticipant,
    this.participants,
    this.lastMessage,
  });

  final String id;
  final bool isGroup;
  final String? name;
  final DateTime createdAt;
  final DateTime? archivedAt;

  /// When this chat was muted for the current user — suppresses push
  /// notifications only.
  final DateTime? mutedAt;

  /// Set only for a 1:1 chat — `null` for a group (see [participants]).
  final ChatParticipant? otherParticipant;

  /// Set only for a group chat — every other participant.
  final List<ChatParticipant>? participants;

  final LastMessagePreview? lastMessage;

  bool get isArchived => archivedAt != null;
  bool get isMuted => mutedAt != null;

  /// A group's own name, or (1:1) the other participant's username.
  String displayName(String fallback) {
    if (isGroup) return name ?? fallback;
    return otherParticipant?.username ?? fallback;
  }

  /// Field overrides for in-place updates without refetching. `mutedAt:
  /// null` means "leave as is"; use [clearMutedAt] to actually unmute.
  Chat copyWith({
    LastMessagePreview? lastMessage,
    DateTime? mutedAt,
    bool clearMutedAt = false,
  }) {
    return Chat(
      id: id,
      isGroup: isGroup,
      name: name,
      createdAt: createdAt,
      archivedAt: archivedAt,
      mutedAt: clearMutedAt ? null : (mutedAt ?? this.mutedAt),
      otherParticipant: otherParticipant,
      participants: participants,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      isGroup: json['isGroup'] as bool,
      name: json['name'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      archivedAt: json['archivedAt'] == null
          ? null
          : DateTime.parse(json['archivedAt'] as String),
      mutedAt: json['mutedAt'] == null
          ? null
          : DateTime.parse(json['mutedAt'] as String),
      otherParticipant: json['otherParticipant'] == null
          ? null
          : ChatParticipant.fromJson(
              json['otherParticipant'] as Map<String, dynamic>,
            ),
      participants: (json['participants'] as List<dynamic>?)
          ?.map((p) => ChatParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      lastMessage: json['lastMessage'] == null
          ? null
          : LastMessagePreview.fromJson(
              json['lastMessage'] as Map<String, dynamic>,
            ),
    );
  }

  @override
  List<Object?> get props => [
    id,
    isGroup,
    name,
    createdAt,
    archivedAt,
    mutedAt,
    otherParticipant,
    participants,
    lastMessage,
  ];
}
