// Coverage for group chat polls: creating one, voting, changing a vote,
// retracting it, and the anonymous-vs-public voter display.
// `_FakePollRepository` stands in for the backend, tracking one vote per
// user per poll the same way poll.model.js's primary key does.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/features/chats/data/message_repository.dart';
import 'package:mobile_messenger/features/chats/data/poll_repository.dart';
import 'package:mobile_messenger/features/chats/presentation/chat_detail_screen.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/models/message.dart';
import 'package:mobile_messenger/models/poll.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';
import 'package:mobile_messenger/services/socket_service.dart';

import '../../support/fake_secure_storage_service.dart';

const _chatId = 'group1';
const _me = User(
  id: 'me',
  username: 'alice',
  email: 'alice@example.com',
  displayName: 'alice',
  emailVerified: true,
);
const _bob = ChatParticipant(id: 'bob', username: 'bob', displayName: 'bob');
const _carol = ChatParticipant(
  id: 'carol',
  username: 'carol',
  displayName: 'carol',
);

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(ApiClient());

  @override
  Future<Chat> getChat(String chatId) async {
    return Chat(
      id: chatId,
      isGroup: true,
      name: 'Weekend Trip',
      createdAt: DateTime(2026, 1, 1),
      participants: const [_bob, _carol],
    );
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(ApiClient());

  @override
  Future<User> fetchCurrentUser() async => _me;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    return const LoginResult(
      user: _me,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }
}

class _FakeMessageRepository extends MessageRepository {
  _FakeMessageRepository({this.initialMessages = const []})
    : super(ApiClient());

  final List<Message> initialMessages;

  @override
  Future<List<Message>> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async => initialMessages;

  @override
  Future<void> markRead(String chatId) async {}
}

class _NoopSocketService extends SocketService {
  @override
  void connect(String accessToken) {}

  @override
  void disconnect() {}

  @override
  void emitTyping(String chatId, bool isTyping) {}
}

/// In-memory stand-in for the backend's poll storage — one vote per
/// (poll, user), mirroring `poll_votes`'s primary key, which is what
/// makes "vote", "change vote", and "retract" the same operations here
/// that they are server-side.
class _FakePollRepository extends PollRepository {
  _FakePollRepository() : super(ApiClient());

  int _counter = 0;
  final Map<String, List<String>> _optionIdsByPoll = {};
  final Map<String, String> _optionTexts = {};
  final Map<String, bool> _isAnonymousByPoll = {};
  // pollId -> (userId -> optionId)
  final Map<String, Map<String, String>> _votesByPoll = {};

  Poll _snapshot(String pollId, {required String viewerId}) {
    final optionIds = _optionIdsByPoll[pollId]!;
    final votes = _votesByPoll[pollId] ?? const {};
    final isAnonymous = _isAnonymousByPoll[pollId]!;
    final options = [
      for (final (index, optionId) in optionIds.indexed)
        PollOption(
          id: optionId,
          text: _optionTexts[optionId]!,
          position: index,
          voteCount: votes.values.where((v) => v == optionId).length,
          voters: isAnonymous
              ? null
              : [
                  for (final MapEntry(key: userId, value: chosen)
                      in votes.entries)
                    if (chosen == optionId) _voterFor(userId),
                ],
        ),
    ];
    return Poll(
      id: pollId,
      messageId: 'msg-$pollId',
      chatId: _chatId,
      creatorId: 'me',
      question: _questionByPoll[pollId]!,
      isAnonymous: isAnonymous,
      createdAt: DateTime(2026, 1, 1, 12),
      totalVotes: votes.length,
      options: options,
      myVoteOptionId: votes[viewerId],
    );
  }

  final Map<String, String> _questionByPoll = {};

  PollVoter _voterFor(String userId) => switch (userId) {
    'me' => const PollVoter(id: 'me', username: 'alice', displayName: 'alice'),
    'bob' => const PollVoter(id: 'bob', username: 'bob', displayName: 'bob'),
    _ => PollVoter(id: userId, username: userId, displayName: userId),
  };

  String _registerPoll({
    required String question,
    required List<String> options,
    required bool isAnonymous,
  }) {
    final pollId = 'poll-${_counter++}';
    final optionIds = [
      for (var index = 0; index < options.length; index++) '$pollId-opt-$index',
    ];
    for (final (index, optionId) in optionIds.indexed) {
      _optionTexts[optionId] = options[index];
    }
    _optionIdsByPoll[pollId] = optionIds;
    _isAnonymousByPoll[pollId] = isAnonymous;
    _votesByPoll[pollId] = {};
    _questionByPoll[pollId] = question;
    return pollId;
  }

  @override
  Future<Message> createPoll(
    String chatId, {
    required String question,
    required List<String> options,
    required bool isAnonymous,
  }) async {
    final pollId = _registerPoll(
      question: question,
      options: options,
      isAnonymous: isAnonymous,
    );
    return Message(
      id: 'msg-$pollId',
      chatId: chatId,
      senderId: 'me',
      type: 'poll',
      createdAt: DateTime(2026, 1, 1, 12),
      status: MessageStatus.sent,
      poll: _snapshot(pollId, viewerId: 'me'),
    );
  }

  @override
  Future<Poll> vote(String chatId, String pollId, String optionId) async {
    _votesByPoll[pollId]!['me'] = optionId;
    return _snapshot(pollId, viewerId: 'me');
  }

  @override
  Future<Poll> retractVote(String chatId, String pollId) async {
    _votesByPoll[pollId]!.remove('me');
    return _snapshot(pollId, viewerId: 'me');
  }

  /// Test-only helper mirroring what `createPoll` already does, for a
  /// test that wants a poll already sitting in history rather than
  /// created through the dialog.
  Poll seedPoll({
    required String question,
    required List<String> options,
    bool isAnonymous = false,
  }) {
    final pollId = _registerPoll(
      question: question,
      options: options,
      isAnonymous: isAnonymous,
    );
    return _snapshot(pollId, viewerId: 'me');
  }
}

Future<void> _pumpGroupChatDetail(
  WidgetTester tester, {
  required _FakeMessageRepository messageRepository,
  required _FakePollRepository pollRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        messageRepositoryProvider.overrideWithValue(messageRepository),
        pollRepositoryProvider.overrideWithValue(pollRepository),
        socketServiceProvider.overrideWithValue(_NoopSocketService()),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
      ],
      child: const MaterialApp(
        home: ChatDetailScreen(chatId: _chatId, title: 'Weekend Trip'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'creating a poll from the attach sheet adds it to the thread with zero votes',
    (tester) async {
      final pollRepository = _FakePollRepository();
      await _pumpGroupChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        pollRepository: pollRepository,
      );

      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poll'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Question'),
        'Where should we eat?',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Option 1'),
        'Pizza',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Option 2'),
        'Sushi',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Where should we eat?'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
      expect(find.text('Sushi'), findsOneWidget);
      expect(find.text('0 votes · Public poll'), findsOneWidget);
    },
  );

  testWidgets('tapping an option casts a vote; tapping it again retracts it', (
    tester,
  ) async {
    final pollRepository = _FakePollRepository();
    final poll = pollRepository.seedPoll(
      question: 'Movie night?',
      options: ['Yes', 'No'],
    );
    final message = Message(
      id: poll.messageId,
      chatId: _chatId,
      senderId: 'bob',
      type: 'poll',
      createdAt: DateTime(2026, 1, 1, 12),
      status: MessageStatus.sent,
      poll: poll,
    );
    await _pumpGroupChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(initialMessages: [message]),
      pollRepository: pollRepository,
    );

    expect(find.text('0 votes · Public poll'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('1 vote · Public poll'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('0 votes · Public poll'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets(
    'voting for a different option changes the vote instead of adding a second one',
    (tester) async {
      final pollRepository = _FakePollRepository();
      final poll = pollRepository.seedPoll(
        question: 'Best season?',
        options: ['Summer', 'Winter'],
      );
      final message = Message(
        id: poll.messageId,
        chatId: _chatId,
        senderId: 'bob',
        type: 'poll',
        createdAt: DateTime(2026, 1, 1, 12),
        status: MessageStatus.sent,
        poll: poll,
      );
      await _pumpGroupChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(initialMessages: [message]),
        pollRepository: pollRepository,
      );

      await tester.tap(find.text('Summer'));
      await tester.pumpAndSettle();
      expect(find.text('1 vote · Public poll'), findsOneWidget);

      await tester.tap(find.text('Winter'));
      await tester.pumpAndSettle();
      // Still exactly one vote total — it moved, it didn't add up.
      expect(find.text('1 vote · Public poll'), findsOneWidget);
    },
  );

  testWidgets(
    'a public poll shows who voted for an option when its count is tapped',
    (tester) async {
      final pollRepository = _FakePollRepository();
      final poll = pollRepository.seedPoll(
        question: 'Coffee or tea?',
        options: ['Coffee', 'Tea'],
      );
      final message = Message(
        id: poll.messageId,
        chatId: _chatId,
        senderId: 'bob',
        type: 'poll',
        createdAt: DateTime(2026, 1, 1, 12),
        status: MessageStatus.sent,
        poll: poll,
      );
      await _pumpGroupChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(initialMessages: [message]),
        pollRepository: pollRepository,
      );

      await tester.tap(find.text('Coffee'));
      await tester.pumpAndSettle();

      // The vote count itself (not the option row) opens the voters sheet.
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      expect(find.text('alice'), findsOneWidget);
    },
  );

  testWidgets('an anonymous poll never shows a voters list', (tester) async {
    final pollRepository = _FakePollRepository();
    final poll = pollRepository.seedPoll(
      question: 'Secret ballot?',
      options: ['Yes', 'No'],
      isAnonymous: true,
    );
    final message = Message(
      id: poll.messageId,
      chatId: _chatId,
      senderId: 'bob',
      type: 'poll',
      createdAt: DateTime(2026, 1, 1, 12),
      status: MessageStatus.sent,
      poll: poll,
    );
    await _pumpGroupChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(initialMessages: [message]),
      pollRepository: pollRepository,
    );

    expect(find.text('0 votes · Anonymous poll'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('1 vote · Anonymous poll'), findsOneWidget);

    // The vote count is not tappable for an anonymous poll — tapping
    // it does nothing (no voters sheet opens).
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
}
