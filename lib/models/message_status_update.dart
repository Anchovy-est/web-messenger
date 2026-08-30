import 'message.dart';

/// A live "these messages are now at least this far along" push from the
/// backend (`message:status` socket event — see
/// backend/src/controllers/message.controller.js `emitStatus`), sent to a
/// chat's room whenever the recipient marks something delivered or read.
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
