import 'package:equatable/equatable.dart';

/// A message's delivery lifecycle. `sending` and `failed` are
/// purely local — a message only ever exists in one of those two states
/// on-device, before the backend has assigned it a real id, so the server
/// never sends them. `sent`/`delivered`/`read` come from the backend (see
/// backend/src/models/message.model.js `toPublicMessage`) and only ever
/// progress forward in that order.
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  factory MessageStatus.fromJson(String value) =>
      MessageStatus.values.byName(value);
}

/// A single message in a chat — `type`/`mediaUrl` support image/video/
/// audio messages as well as text, matching
/// backend/migrations/…init-messages-table.js.
///
/// A deleted message isn't removed — `deletedAt` gets set and
/// `body`/`mediaUrl` come back null from the backend, but the message
/// stays in the list as a tombstone in its original position; see
/// [isDeleted] and `_MessageBubble` in chat_detail_screen.dart.
class Message extends Equatable {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    required this.status,
    this.body,
    this.mediaUrl,
    this.editedAt,
    this.deletedAt,
  });

  final String id;
  final String chatId;
  final String? senderId;
  final String type;
  final String? body;
  final String? mediaUrl;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final MessageStatus status;

  bool get isDeleted => deletedAt != null;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      senderId: json['senderId'] as String?,
      type: json['type'] as String,
      body: json['body'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      editedAt: json['editedAt'] == null
          ? null
          : DateTime.parse(json['editedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      status: MessageStatus.fromJson(json['status'] as String),
    );
  }

  /// [body] overrides the stored value when given — used by
  /// `ChatDetailController` to swap a message's encrypted `body` for its
  /// decrypted plaintext once `EncryptionService` has resolved it,
  /// without needing to reconstruct the whole [Message].
  Message copyWith({MessageStatus? status, String? body}) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      type: type,
      body: body ?? this.body,
      mediaUrl: mediaUrl,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
    id,
    chatId,
    senderId,
    type,
    body,
    mediaUrl,
    createdAt,
    editedAt,
    deletedAt,
    status,
  ];
}
