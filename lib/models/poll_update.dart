import 'poll.dart';

/// A live tally push from the backend (`poll:updated` socket event — see
/// backend/src/controllers/poll.controller.js `broadcastPollUpdate`),
/// sent to a chat's room whenever anyone casts, changes, or retracts a
/// vote. [poll] never carries [Poll.myVoteOptionId] — see that field's
/// doc comment for why a value shared identically with every recipient
/// could never safely mean "your own vote".
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
