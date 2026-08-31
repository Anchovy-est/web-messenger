// Group-chat-specific coverage for ChatDetailController/ChatDetailScreen
// — the 1:1 case is covered exhaustively by chat_detail_flow_test.dart;
// this file is specifically about the three things that only exist once
// a chat has more than two participants: per-recipient message wrapping
// (no single shared chat key the way a 1:1 chat has), sender-name
// labels on incoming bubbles, and a device being able to read its own
// past messages again after a reload.
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

final _crypto = EncryptionService();
late final SimpleKeyPair _aliceKeyPair;
late final SecretKey _aliceSelfKey; // "me"'s key with itself
late final SecretKey _aliceBobKey; // "me" <-> bob, symmetric either way
late final SecretKey _aliceCarolKey; // "me" <-> carol, symmetric either way

Future<void> _prepareCrypto() async {
  _aliceKeyPair = await _crypto.keyPairFromSeed(
    base64Decode(testIdentityPrivateKeySeed),
  );
  final alicePublicKey = await _crypto.exportPublicKey(_aliceKeyPair);
  final bobKeyPair = await _crypto.generateIdentityKeyPair();
  final carolKeyPair = await _crypto.generateIdentityKeyPair();
  final bobPublicKey = await _crypto.exportPublicKey(bobKeyPair);
  final carolPublicKey = await _crypto.exportPublicKey(carolKeyPair);

  _aliceSelfKey = (await _crypto.deriveChatKey(
    myKeyPair: _aliceKeyPair,
    peerPublicKeyBase64: alicePublicKey,
    chatId: _chatId,
  ))!;
  _aliceBobKey = (await _crypto.deriveChatKey(
    myKeyPair: _aliceKeyPair,
    peerPublicKeyBase64: bobPublicKey,
    chatId: _chatId,
  ))!;
  _aliceCarolKey = (await _crypto.deriveChatKey(
    myKeyPair: _aliceKeyPair,
    peerPublicKeyBase64: carolPublicKey,
    chatId: _chatId,
  ))!;

  _bobParticipant = ChatParticipant(
    id: _bob.id,
    username: _bob.username,
    displayName: _bob.displayName,
    publicKey: bobPublicKey,
  );
  _carolParticipant = ChatParticipant(
    id: _carol.id,
    username: _carol.username,
    displayName: _carol.displayName,
    publicKey: carolPublicKey,
  );
}

late ChatParticipant _bobParticipant;
late ChatParticipant _carolParticipant;

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(ApiClient());

  @override
  Future<Chat> getChat(String chatId) async {
    return Chat(
      id: chatId,
      isGroup: true,
      name: 'Weekend Trip',
      createdAt: DateTime(2026, 1, 1),
      participants: [_bobParticipant, _carolParticipant],
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
  final List<String> sentBodies = [];

  @override
  Future<List<Message>> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async => initialMessages;

  @override
  Future<void> markRead(String chatId) async {}

  @override
  Future<Message> sendMessage(String chatId, String body) async {
    sentBodies.add(body);
    return Message(
      id: 'sent-${sentBodies.length}',
      chatId: chatId,
      senderId: _me.id,
      type: 'text',
      body: body,
      createdAt: DateTime(2026, 1, 1, 12),
      status: MessageStatus.sent,
    );
  }
}

class _NoopSocketService extends SocketService {
  @override
  void connect(String accessToken) {}

  @override
  void disconnect() {}

  @override
  void emitTyping(String chatId, bool isTyping) {}
}

Future<void> _pumpGroupChatDetail(
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
        home: ChatDetailScreen(chatId: _chatId, title: 'Weekend Trip'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_prepareCrypto);

  testWidgets(
    'sending a group text message wraps it once per participant, including a decryptable copy for myself',
    (tester) async {
      final repository = _FakeMessageRepository();
      await _pumpGroupChatDetail(tester, messageRepository: repository);

      await tester.enterText(find.byType(TextField), 'see you at 6');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(repository.sentBodies, hasLength(1));
      final envelopeMap =
          jsonDecode(repository.sentBodies.single) as Map<String, dynamic>;
      // One entry per current participant — bob, carol, and myself.
      expect(envelopeMap.keys.toSet(), {'me', 'bob', 'carol'});

      final decryptedForMe = await _crypto.decryptTextForRecipient(
        envelopeMapJson: repository.sentBodies.single,
        myUserId: 'me',
        senderKey: _aliceSelfKey,
      );
      final decryptedForBob = await _crypto.decryptTextForRecipient(
        envelopeMapJson: repository.sentBodies.single,
        myUserId: 'bob',
        senderKey: _aliceBobKey,
      );
      final decryptedForCarol = await _crypto.decryptTextForRecipient(
        envelopeMapJson: repository.sentBodies.single,
        myUserId: 'carol',
        senderKey: _aliceCarolKey,
      );
      expect(decryptedForMe, 'see you at 6');
      expect(decryptedForBob, 'see you at 6');
      expect(decryptedForCarol, 'see you at 6');

      // Shows as sent, decrypted, in my own thread.
      expect(find.text('see you at 6'), findsOneWidget);
    },
  );

  testWidgets(
    'a received group message from bob decrypts using the pairwise key shared with bob, and is labeled with his name',
    (tester) async {
      final envelopeForMe = await _crypto.encryptTextForRecipients({
        'me': _aliceBobKey, // the key bob and I share, symmetric either way
      }, "let's leave at 9");
      final incoming = Message(
        id: 'from-bob-1',
        chatId: _chatId,
        senderId: 'bob',
        type: 'text',
        body: envelopeForMe,
        createdAt: DateTime(2026, 1, 1, 13),
        status: MessageStatus.sent,
      );

      final repository = _FakeMessageRepository(initialMessages: [incoming]);
      await _pumpGroupChatDetail(tester, messageRepository: repository);

      expect(find.text("let's leave at 9"), findsOneWidget);
      expect(find.text('bob'), findsOneWidget); // sender-name label
    },
  );

  testWidgets(
    'my own previously-sent group message is still decryptable after a fresh load',
    (tester) async {
      // Simulates history loaded on a fresh app start — a message this
      // device sent earlier, wrapped (including for itself) exactly the
      // way `_attemptSend` does.
      final envelopeMap = await _crypto.encryptTextForRecipients({
        'me': _aliceSelfKey,
        'bob': _aliceBobKey,
      }, 'already sent this earlier');
      final myOldMessage = Message(
        id: 'my-old-1',
        chatId: _chatId,
        senderId: 'me',
        type: 'text',
        body: envelopeMap,
        createdAt: DateTime(2026, 1, 1, 10),
        status: MessageStatus.read,
      );

      final repository = _FakeMessageRepository(
        initialMessages: [myOldMessage],
      );
      await _pumpGroupChatDetail(tester, messageRepository: repository);

      expect(find.text('already sent this earlier'), findsOneWidget);
      // My own message never gets a sender-name label.
      expect(find.text('alice'), findsNothing);
    },
  );
}
