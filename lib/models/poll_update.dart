import 'poll.dart';

/// A live tally push from the backend (`poll:updated` socket event).
/// Never carries [Poll.myVoteOptionId] — that's per-viewer.
class PollUpdate {
  const PollUpdate({required this.chatId, required this.poll});

  final String chatId;
  final Poll poll;

  factory PollUpdate.fromJson(Map<String, dynamic> json) {
    return PollUpdate(
      chatId: json['chatId'] as String,
      poll: Poll.fromJson(json['poll'] as Map<String, dynamic>),
    );
  }
}
