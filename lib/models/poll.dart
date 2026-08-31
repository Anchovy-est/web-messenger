import 'package:equatable/equatable.dart';

/// One person who voted for a [PollOption] — only ever present on a
/// non-anonymous poll's options; see [PollOption.voters].
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

/// One choice in a [Poll], with its live vote count — see
/// backend/src/models/poll.model.js `toPublicPoll`.
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

  /// Who voted for this option — `null` (the key is absent from the
  /// server's JSON entirely, not just an empty list) for an anonymous
  /// poll's options. Never trust a non-null value here as "everyone who
  /// voted" unless [Poll.isAnonymous] is false — see that field's doc
  /// comment.
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

/// A poll message's actual content. Rides along embedded in its own
/// [Message] (`Message.poll`, only ever non-null for a `type: 'poll'`
/// message) rather than being a separate thing the client fetches on the
/// side — see backend/src/services/message.service.js `attachPolls`.
///
/// Unlike a text message's `body`, a poll's `question`/options are *not*
/// end-to-end encrypted — the server has to actively read them to
/// enforce one-vote-per-user, tally results, and push live updates,
/// which real E2EE makes impossible. See the migration that created
/// `polls` (backend/migrations/…create-polls-tables.js) for the full
/// reasoning. What *is* still protected is who's allowed to see a poll
/// at all (ordinary chat-membership checks, same as every message) and,
/// for an anonymous poll, who voted for what.
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

  /// Fixed at creation. `false` (public): every option lists who voted
  /// for it — see [PollOption.voters]. `true` (anonymous): the server
  /// never sends voter identity for this poll to anyone but each voter
  /// themselves, about their own vote (see [myVoteOptionId]) — not just
  /// "the UI doesn't show it", the data itself never crosses the wire.
  final bool isAnonymous;
  final DateTime createdAt;
  final int totalVotes;
  final List<PollOption> options;

  /// The current device's own user's vote, or `null` if they haven't
  /// voted (or retracted). Only ever populated from a REST response
  /// (poll creation, fetch, vote, retract) — a realtime `poll:updated`
  /// broadcast deliberately never carries this field at all, since it's
  /// shared identically with everyone in the chat and this is inherently
  /// per-viewer; see `ChatDetailController._onPollUpdated` and
  /// backend/src/controllers/poll.controller.js `forBroadcast`.
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

  /// Applies a realtime tally update (question/options/vote counts —
  /// never [myVoteOptionId], which a broadcast never carries; see that
  /// field's doc comment) on top of this poll's own, already-known,
  /// current vote. Used by `ChatDetailController._onPollUpdated` so a
  /// `poll:updated` push updates everyone's view of the *tally* without
  /// ever touching what this specific device already knows about its own
  /// vote.
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
