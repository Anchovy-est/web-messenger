/// A live "someone is/isn't typing" push — the `typing` socket event,
/// relayed by the backend straight from one participant's client
/// to the other's (see backend/src/sockets/index.js) and never persisted
/// anywhere, unlike a real message.
class TypingUpdate {
  const TypingUpdate({
    required this.chatId,
    required this.userId,
    required this.isTyping,
  });

  final String chatId;
  final String userId;
  final bool isTyping;

  factory TypingUpdate.fromJson(Map<String, dynamic> json) {
    return TypingUpdate(
      chatId: json['chatId'] as String,
      userId: json['userId'] as String,
      isTyping: json['isTyping'] as bool,
    );
  }
}
