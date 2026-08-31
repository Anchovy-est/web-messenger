import 'package:equatable/equatable.dart';

/// One person who voted for a [PollOption] — only present on a
/// non-anonymous poll.
class PollVoter extends Equatable {
  const PollVoter({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory PollVoter.fromJson(Map<String, dynamic> json) {
    return PollVoter(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, username, displayName, avatarUrl];
}

/// One choice in a [Poll], with its live vote count.
class PollOption extends Equatable {
  const PollOption({
    required this.id,
    required this.text,
    required this.position,
    required this.voteCount,
    this.voters,
  });

  final String id;
  final String text;
  final int position;
  final int voteCount;

  /// Who voted for this option — `null` (key absent, not just empty)
  /// for an anonymous poll.
  final List<PollVoter>? voters;

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['id'] as String,
      text: json['text'] as String,
      position: json['position'] as int,
      voteCount: json['voteCount'] as int,
      voters: (json['voters'] as List<dynamic>?)
          ?.map((v) => PollVoter.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, text, position, voteCount, voters];
}

/// A poll message's content. Embedded in its own [Message] rather than
/// fetched separately. Unlike a text message's `body`, a poll's
/// question/options aren't end-to-end encrypted — the server needs to
/// read them to tally votes and enforce one-vote-per-user.
class Poll extends Equatable {
  const Poll({
    required this.id,
    required this.messageId,
    required this.chatId,
    required this.creatorId,
    required this.question,
    required this.isAnonymous,
    required this.createdAt,
    required this.totalVotes,
    required this.options,
    this.myVoteOptionId,
  });

  final String id;
  final String messageId;
  final String chatId;
  final String? creatorId;
  final String question;

  /// Fixed at creation. Anonymous polls never reveal voter identity to
  /// anyone but the voter themselves (see [myVoteOptionId]).
  final bool isAnonymous;
  final DateTime createdAt;
  final int totalVotes;
  final List<PollOption> options;

  /// This device's own vote, or null. Only ever set from a REST
  /// response — a realtime broadcast never carries it, since it's
  /// per-viewer.
  final String? myVoteOptionId;

  factory Poll.fromJson(Map<String, dynamic> json) {
    return Poll(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      chatId: json['chatId'] as String,
      creatorId: json['creatorId'] as String?,
      question: json['question'] as String,
      isAnonymous: json['isAnonymous'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      totalVotes: json['totalVotes'] as int,
      options: (json['options'] as List<dynamic>? ?? const [])
          .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      myVoteOptionId: json['myVoteOptionId'] as String?,
    );
  }

  /// Applies a realtime tally update on top of this poll's own,
  /// already-known vote — never overwritten by a broadcast.
  Poll withBroadcastTally(Poll broadcast) {
    return Poll(
      id: broadcast.id,
      messageId: broadcast.messageId,
      chatId: broadcast.chatId,
      creatorId: broadcast.creatorId,
      question: broadcast.question,
      isAnonymous: broadcast.isAnonymous,
      createdAt: broadcast.createdAt,
      totalVotes: broadcast.totalVotes,
      options: broadcast.options,
      myVoteOptionId: myVoteOptionId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    messageId,
    chatId,
    creatorId,
    question,
    isAnonymous,
    createdAt,
    totalVotes,
    options,
    myVoteOptionId,
  ];
}
