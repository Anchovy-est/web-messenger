import 'message.dart';

/// A live "these messages reached at least this status" push from the
/// backend (`message:status` socket event).
class MessageStatusUpdate {
  const MessageStatusUpdate({
    required this.chatId,
    required this.messageIds,
    required this.status,
  });

  final String chatId;
  final List<String> messageIds;
  final MessageStatus status;

  factory MessageStatusUpdate.fromJson(Map<String, dynamic> json) {
    return MessageStatusUpdate(
      chatId: json['chatId'] as String,
      messageIds: (json['messageIds'] as List).cast<String>(),
      status: MessageStatus.fromJson(json['status'] as String),
    );
  }
}
