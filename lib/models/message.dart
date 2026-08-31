import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import 'poll.dart';

/// A message's delivery lifecycle. `sending`/`failed` are local-only,
/// before the backend assigns a real id. `sent`/`delivered`/`read` come
/// from the backend and only progress forward.
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  factory MessageStatus.fromJson(String value) =>
      MessageStatus.values.byName(value);
}

/// A single message in a chat. A deleted message isn't removed —
/// `deletedAt` is set and `body`/`mediaUrl` come back null, so it stays
/// in place as a tombstone.
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
    this.localBytes,
    this.poll,
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

  /// This message's poll content — only non-null when [type] is
  /// `'poll'`. Not end-to-end encrypted, unlike [body] — see [Poll].
  final Poll? poll;

  /// Original, plaintext, not-yet-uploaded media bytes for a still-
  /// `sending`/`failed` message — a local rendering/retry aid, never
  /// sent to or received from the backend.
  final Uint8List? localBytes;

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
      poll: json['poll'] == null
          ? null
          : Poll.fromJson(json['poll'] as Map<String, dynamic>),
    );
  }

  /// [body]/[poll] override the stored value when given — e.g. swapping
  /// in decrypted plaintext, or a fresher poll tally.
  Message copyWith({MessageStatus? status, String? body, Poll? poll}) {
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
      localBytes: localBytes,
      poll: poll ?? this.poll,
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
    poll,
  ];
}
