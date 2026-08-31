/// A live "someone is/isn't typing" push — never persisted.
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
