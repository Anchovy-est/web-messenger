// Coverage for the in-chat message search bar added in Phase 9 — see
// MessageSearchController's class doc comment for why this has to be
// entirely client-side (searching only text this device has already
// decrypted), unlike server-side search a non-E2EE app could offer.
// The crypto/decrypt scaffolding here mirrors chat_detail_flow_test.dart.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/features/chats/data/message_repository.dart';
import 'package:mobile_messenger/features/chats/presentation/chat_detail_screen.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/models/message.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';
import 'package:mobile_messenger/services/encryption_service.dart';
import 'package:mobile_messenger/services/socket_service.dart';

import '../../support/fake_secure_storage_service.dart';

const _chatId = 'chat1';
const _me = User(
  id: 'me',
  username: 'alice',
  email: 'alice@example.com',
  displayName: 'alice',
  emailVerified: true,
);

final _crypto = EncryptionService();
late final SimpleKeyPair _aliceKeyPair;
late final String _bobPublicKey;
late final SecretKey _chatKey;
final _encryptedBody = <String, String>{};

const _fixtureBodies = [
  'Hi Alice',
  'hello there',
  'hello world',
  'this one is deleted but says hello',
];

Future<void> _prepareCrypto() async {
  _aliceKeyPair = await _crypto.keyPairFromSeed(
    base64Decode(testIdentityPrivateKeySeed),
  );
  final bobKeyPair = await _crypto.generateIdentityKeyPair();
  _bobPublicKey = await _crypto.exportPublicKey(bobKeyPair);
  _chatKey = (await _crypto.deriveChatKey(
    myKeyPair: _aliceKeyPair,
    peerPublicKeyBase64: _bobPublicKey,
    chatId: _chatId,
  ))!;
  for (final plaintext in _fixtureBodies) {
    _encryptedBody[plaintext] = await _crypto.encryptText(_chatKey, plaintext);
  }
}

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(ApiClient());

  @override
  Future<Chat> getChat(String chatId) async {
    return Chat(
      id: chatId,
      isGroup: false,
      createdAt: DateTime(2026, 1, 1),
      otherParticipant: ChatParticipant(
        id: 'bob',
        username: 'bob',
        displayName: 'bob',
        publicKey: _bobPublicKey,
      ),
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

/// [body] is looked up in [_encryptedBody] (populated by [_prepareCrypto])
/// so call sites stay plain literals while the controller still decrypts
/// real ciphertext, same as chat_detail_flow_test.dart's `_message`.
Message _message({
  required String id,
  required String senderId,
  required String body,
  required DateTime createdAt,
  DateTime? deletedAt,
}) {
  return Message(
    id: id,
    chatId: _chatId,
    senderId: senderId,
    type: 'text',
    body: _encryptedBody[body] ?? body,
    createdAt: createdAt,
    deletedAt: deletedAt,
    status: MessageStatus.sent,
  );
}

Future<void> _pumpChatDetail(
  WidgetTester tester, {
  required _FakeMessageRepository messageRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        messageRepositoryProvider.overrideWithValue(messageRepository),
        socketServiceProvider.overrideWithValue(_NoopSocketService()),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
      ],
      child: const MaterialApp(
        home: ChatDetailScreen(chatId: _chatId, title: 'bob'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_prepareCrypto);

  Future<void> pumpThreeMessages(WidgetTester tester) => _pumpChatDetail(
    tester,
    messageRepository: _FakeMessageRepository(
      initialMessages: [
        _message(
          id: 'm1',
          senderId: 'bob',
          body: 'Hi Alice',
          createdAt: DateTime(2026, 1, 1, 12, 0),
        ),
        _message(
          id: 'm2',
          senderId: _me.id,
          body: 'hello there',
          createdAt: DateTime(2026, 1, 1, 12, 1),
        ),
        _message(
          id: 'm3',
          senderId: 'bob',
          body: 'hello world',
          createdAt: DateTime(2026, 1, 1, 12, 2),
        ),
        _message(
          id: 'm4',
          senderId: 'bob',
          body: 'this one is deleted but says hello',
          createdAt: DateTime(2026, 1, 1, 12, 3),
          deletedAt: DateTime(2026, 1, 1, 12, 4),
        ),
      ],
    ),
  );

  testWidgets('the search bar is hidden until the search icon is tapped', (
    tester,
  ) async {
    await pumpThreeMessages(tester);

    expect(find.text('bob'), findsOneWidget); // normal app bar title
    expect(find.text('Search in this chat'), findsNothing);
  });

  testWidgets(
    'typing a query shows a match counter and previous/next cycle through matches',
    (tester) async {
      await pumpThreeMessages(tester);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      final searchField = find.ancestor(
        of: find.text('Search in this chat'),
        matching: find.byType(TextField),
      );
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'hello');
      await tester.pumpAndSettle();

      // Two live matches ("hello there", "hello world") — the deleted
      // "...says hello" message must not count as a third.
      expect(find.text('2/2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up)); // previous
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down)); // next
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);

      // Wraps back around past the last match.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
    },
  );

  testWidgets('closing the search bar restores the normal app bar', (
    tester,
  ) async {
    await pumpThreeMessages(tester);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    final searchField = find.ancestor(
      of: find.text('Search in this chat'),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'hello');
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('bob'), findsOneWidget); // normal app bar title back
    expect(find.text('2/2'), findsNothing);
  });

  testWidgets('a query with no matches shows a 0/0 counter', (tester) async {
    await pumpThreeMessages(tester);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    final searchField = find.ancestor(
      of: find.text('Search in this chat'),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.text('0/0'), findsOneWidget);
  });
}
