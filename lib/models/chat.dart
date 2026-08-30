import 'package:equatable/equatable.dart';

/// The other 1:1 participant in a chat — see backend/src/models/
/// chat.model.js `toPublicChat`. Kept separate from the similarly-shaped
/// `InvitationParticipant` since the two responses are independent and
/// may diverge (e.g. online status only ever makes sense here).
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

  /// This participant's end-to-end encryption public key — see
  /// `lib/services/encryption_service.dart`. Null until they've logged in
  /// at least once and registered a key; a chat with a null key here
  /// can't yet derive a shared key, so sending/decrypting degrades
  /// gracefully rather than crashing (see `ChatDetailController`).
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

  /// [body] overrides the stored value when given — used by
  /// `ChatListController` to swap this preview's encrypted `body` for
  /// its decrypted plaintext.
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
    this.lastMessage,
  });

  final String id;
  final bool isGroup;
  final String? name;
  final DateTime createdAt;
  final DateTime? archivedAt;

  /// When this chat was muted *for the current user* — muting is
  /// per-user, per-chat, same as archiving (see
  /// backend/src/models/chat.model.js `setMuted`). Suppresses push
  /// notifications only; the chat, its messages, and realtime socket
  /// delivery are all unaffected — a muted chat still updates live if
  /// it's open on screen.
  final DateTime? mutedAt;
  final ChatParticipant? otherParticipant;
  final LastMessagePreview? lastMessage;

  bool get isArchived => archivedAt != null;
  bool get isMuted => mutedAt != null;

  /// What to show as the chat's title — a group's own name, or (for a
  /// 1:1 chat) the other participant's name, derived client-side per the
  /// backend's design (see migrations/…init-chats-tables.js).
  String displayName(String fallback) {
    if (isGroup) return name ?? fallback;
    return otherParticipant?.username ?? fallback;
  }

  /// [lastMessage] overrides the stored value when given — used by
  /// `ChatListController` to swap in a decrypted preview without
  /// reconstructing every other field. [mutedAt]/[clearMutedAt] update
  /// the mute state in place — used by [ChatListScreen]'s mute toggle to
  /// update one chat's entry in an already-loaded list without a full
  /// refetch. `mutedAt: null` (the default) means "leave it as it was",
  /// same as every other field here — [clearMutedAt] is the explicit way
  /// to actually set it back to null (unmute), since a plain nullable
  /// parameter can't distinguish "no change" from "change to null".
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
    lastMessage,
  ];
}
