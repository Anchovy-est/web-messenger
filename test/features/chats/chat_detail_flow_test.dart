import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/features/chats/data/message_repository.dart';
import 'package:mobile_messenger/features/chats/presentation/chat_detail_controller.dart';
import 'package:mobile_messenger/features/chats/presentation/chat_detail_screen.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/models/message.dart';
import 'package:mobile_messenger/models/message_status_update.dart';
import 'package:mobile_messenger/models/typing_update.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';
import 'package:mobile_messenger/services/encryption_service.dart';
import 'package:mobile_messenger/services/socket_service.dart';

import '../../support/fake_secure_storage_service.dart';

// --- End-to-end encryption test scaffolding --------------------------------
//
// `ChatDetailController` now requires a real, derivable chat key to send
// or decrypt anything (see its class doc comment) — these tests exercise
// the real `EncryptionService` (not a fake/no-op), with a fixed identity
// keypair for "me" (matching `FakeSecureStorageService`'s default, so
// `_pumpChatDetail` needs no extra wiring for it) and a freshly-generated
// one standing in for "bob", wired in via [_FakeChatRepository] so
// `ChatDetailController._prepareEncryption` can derive the same chat key
// a real client would. `_encryptedBody` pre-encrypts every literal
// plaintext string used as fixture/pushed-message content below, so
// `_message()` and friends stay simple call sites rather than every test
// awaiting its own encryption step.
final _crypto = EncryptionService();
late final SimpleKeyPair _aliceKeyPair;
late final String _bobPublicKey;
late final SecretKey _chatKey;
final _encryptedBody = <String, String>{};

const _chatId = 'chat1';

/// A genuinely-decodable minimal 1x1 PNG (matches the fixture pattern
/// used on the backend — see backend/src/routes/user.avatar.test.js).
/// `Image.memory` actually runs its bytes through the platform's real
/// image codec, so arbitrary placeholder bytes (fine for the *encryption*
/// round-trip, which doesn't care what the bytes mean) throw "Invalid
/// image data" partway through rendering and fail the test — using a
/// real image avoids that without weakening what's actually under test
/// here (the decrypt pipeline, not image-format validity).
const _validPngBytes = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  4,
  0,
  0,
  0,
  181,
  28,
  12,
  2,
  0,
  0,
  0,
  11,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  100,
  248,
  15,
  0,
  1,
  5,
  1,
  1,
  39,
  24,
  227,
  102,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

const _fixtureBodies = [
  'Hi Alice',
  'Hi Bob',
  'Hi Alice!',
  'Only once, please',
  'Seen this?',
  'hi',
  'Original text',
  'Untouched',
  "Bob's message",
  "Bob's original",
  "Bob's corrected message",
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

/// Stands in for `ChatRepository` — `ChatDetailController` fetches the
/// chat once, at startup, purely to read the other participant's public
/// key (see `_prepareEncryption`).
class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository(this._peerPublicKey, {this.mutedAt}) : super(ApiClient());

  final String? _peerPublicKey;
  DateTime? mutedAt;
  final List<String> muteCalls = [];
  final List<String> unmuteCalls = [];

  @override
  Future<Chat> getChat(String chatId) async {
    return Chat(
      id: chatId,
      isGroup: false,
      createdAt: DateTime(2026, 1, 1),
      mutedAt: mutedAt,
      otherParticipant: ChatParticipant(
        id: 'bob',
        username: 'bob',
        displayName: 'bob',
        publicKey: _peerPublicKey,
      ),
    );
  }

  @override
  Future<Chat> mute(String chatId) async {
    muteCalls.add(chatId);
    mutedAt = DateTime(2026, 1, 2);
    return getChat(chatId);
  }

  @override
  Future<Chat> unmute(String chatId) async {
    unmuteCalls.add(chatId);
    mutedAt = null;
    return getChat(chatId);
  }
}

const _me = User(
  id: 'me',
  username: 'alice',
  email: 'alice@example.com',
  displayName: 'alice',
  emailVerified: true,
);

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
  _FakeMessageRepository({
    this.initialMessages = const [],
    this.errorOnList,
    this.errorOnSend,
    this.errorOnEdit,
    this.errorOnDelete,
    this.errorOnSendMedia,
    this.sendDelay = Duration.zero,
  }) : super(ApiClient());

  final List<Message> initialMessages;
  final ApiException? errorOnList;
  // Mutable — a test can send/edit/delete once with an error set, then
  // clear it and retry, without needing a second repository instance.
  ApiException? errorOnSend;
  ApiException? errorOnEdit;
  ApiException? errorOnDelete;
  ApiException? errorOnSendMedia;
  final Duration sendDelay;
  final List<String> sentBodies = [];
  final List<Uint8List> sentMediaBytes = [];
  // Keyed by the `mediaUrl` a sent/pushed message points at — stands in
  // for the backend's `uploads/messages/` disk storage, so `downloadMedia`
  // has something to serve back (still-encrypted, exactly like the real
  // static file route would). Tests exercising a *received* media message
  // populate this directly before pushing it; a *sent* one is populated
  // automatically by `sendMediaMessage` below.
  final Map<String, Uint8List> mediaStore = {};
  final List<String> markedDeliveredChatIds = [];
  final List<String> markedReadChatIds = [];
  final List<(String messageId, String body)> editedMessages = [];
  final List<String> deletedMessageIds = [];
  int _sendCount = 0;
  int _sendMediaCount = 0;

  @override
  Future<List<Message>> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async {
    if (errorOnList != null) throw errorOnList!;
    return initialMessages;
  }

  @override
  Future<Message> sendMessage(String chatId, String body) async {
    if (sendDelay > Duration.zero) await Future<void>.delayed(sendDelay);
    if (errorOnSend != null) throw errorOnSend!;
    sentBodies.add(body);
    _sendCount++;
    return Message(
      id: 'sent-$_sendCount',
      chatId: chatId,
      senderId: _me.id,
      type: 'text',
      body: body,
      createdAt: DateTime(2026, 1, 1, 12),
      status: MessageStatus.sent,
    );
  }

  @override
  Future<Message> sendMediaMessage(
    String chatId,
    Uint8List bytes,
    String type,
  ) async {
    if (errorOnSendMedia != null) throw errorOnSendMedia!;
    sentMediaBytes.add(bytes);
    _sendMediaCount++;
    final url = '/uploads/messages/sent-media-$_sendMediaCount.enc';
    mediaStore[url] = bytes;
    return Message(
      id: 'sent-media-$_sendMediaCount',
      chatId: chatId,
      senderId: _me.id,
      type: type,
      mediaUrl: url,
      createdAt: DateTime(2026, 1, 1, 12),
      status: MessageStatus.sent,
    );
  }

  @override
  Future<Uint8List> downloadMedia(String mediaUrl) async {
    final bytes = mediaStore[mediaUrl];
    if (bytes == null) {
      throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'No such media.',
      );
    }
    return bytes;
  }

  @override
  Future<void> markDelivered(String chatId) async {
    markedDeliveredChatIds.add(chatId);
  }

  @override
  Future<void> markRead(String chatId) async {
    markedReadChatIds.add(chatId);
  }

  @override
  Future<Message> editMessage(
    String chatId,
    String messageId,
    String body,
  ) async {
    if (errorOnEdit != null) throw errorOnEdit!;
    editedMessages.add((messageId, body));
    final original = initialMessages
        .where((m) => m.id == messageId)
        .firstOrNull;
    return Message(
      id: messageId,
      chatId: chatId,
      senderId: _me.id,
      type: 'text',
      body: body,
      createdAt: original?.createdAt ?? DateTime(2026, 1, 1, 12),
      editedAt: DateTime(2026, 1, 1, 12, 30),
      status: original?.status ?? MessageStatus.sent,
    );
  }

  @override
  Future<Message> deleteMessage(String chatId, String messageId) async {
    if (errorOnDelete != null) throw errorOnDelete!;
    deletedMessageIds.add(messageId);
    final original = initialMessages
        .where((m) => m.id == messageId)
        .firstOrNull;
    return Message(
      id: messageId,
      chatId: chatId,
      senderId: _me.id,
      type: 'text',
      createdAt: original?.createdAt ?? DateTime(2026, 1, 1, 12),
      deletedAt: DateTime(2026, 1, 1, 12, 30),
      status: original?.status ?? MessageStatus.sent,
    );
  }
}

/// Lets a test push `message:new`/`message:status` events straight into
/// `ChatDetailController`'s subscriptions, standing in for a real socket
/// push from the backend (that round trip is covered by
/// backend/src/routes/message.routes.test.js).
class _ControllableSocketService extends SocketService {
  final _messageController = StreamController<Message>.broadcast();
  final _statusController = StreamController<MessageStatusUpdate>.broadcast();
  final _typingController = StreamController<TypingUpdate>.broadcast();
  final _editedController = StreamController<Message>.broadcast();
  final _deletedController = StreamController<Message>.broadcast();
  final List<TypingUpdate> emittedTyping = [];

  @override
  Stream<Message> get messageStream => _messageController.stream;

  @override
  Stream<MessageStatusUpdate> get statusStream => _statusController.stream;

  @override
  Stream<TypingUpdate> get typingStream => _typingController.stream;

  @override
  Stream<Message> get editedMessageStream => _editedController.stream;

  @override
  Stream<Message> get deletedMessageStream => _deletedController.stream;

  @override
  void connect(String accessToken) {}

  @override
  void disconnect() {}

  @override
  void emitTyping(String chatId, bool isTyping) {
    emittedTyping.add(
      TypingUpdate(chatId: chatId, userId: _me.id, isTyping: isTyping),
    );
  }

  void pushIncoming(Message message) => _messageController.add(message);
  void pushStatus(MessageStatusUpdate update) => _statusController.add(update);
  void pushTyping(TypingUpdate update) => _typingController.add(update);
  void pushEdited(Message message) => _editedController.add(message);
  void pushDeleted(Message message) => _deletedController.add(message);
}

/// [body] is looked up in [_encryptedBody] (pre-populated by
/// [_prepareCrypto]) so every call site here stays a plain, synchronous
/// literal — `ChatDetailController` decrypts real ciphertext, so a
/// fixture/pushed message needs to actually carry some, not the raw
/// plaintext a pre-Phase-20 test could get away with.
Message _message({
  required String id,
  required String senderId,
  required String body,
  DateTime? createdAt,
  MessageStatus status = MessageStatus.sent,
}) {
  return Message(
    id: id,
    chatId: 'chat1',
    senderId: senderId,
    type: 'text',
    body: _encryptedBody[body] ?? body,
    createdAt: createdAt ?? DateTime(2026, 1, 1, 12),
    status: status,
  );
}

Future<void> _pumpChatDetail(
  WidgetTester tester, {
  required _FakeMessageRepository messageRepository,
  required _ControllableSocketService socketService,
  _FakeChatRepository? chatRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        messageRepositoryProvider.overrideWithValue(messageRepository),
        socketServiceProvider.overrideWithValue(socketService),
        chatRepositoryProvider.overrideWithValue(
          chatRepository ?? _FakeChatRepository(_bobPublicKey),
        ),
      ],
      child: const MaterialApp(
        home: ChatDetailScreen(chatId: 'chat1', title: 'bob'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_prepareCrypto);

  testWidgets('shows message history with sent/received alignment', (
    tester,
  ) async {
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: 'bob', body: 'Hi Alice'),
          _message(id: 'm2', senderId: _me.id, body: 'Hi Bob'),
        ],
      ),
      socketService: _ControllableSocketService(),
    );

    expect(find.text('Hi Alice'), findsOneWidget);
    expect(find.text('Hi Bob'), findsOneWidget);

    final aligns = tester.widgetList<Align>(find.byType(Align)).toList();
    expect(aligns[0].alignment, Alignment.centerLeft); // bob's message
    expect(aligns[1].alignment, Alignment.centerRight); // my own message
  });

  testWidgets('shows an empty state with no messages', (tester) async {
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(),
      socketService: _ControllableSocketService(),
    );

    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
  });

  testWidgets('shows an error with retry when history fails to load', (
    tester,
  ) async {
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        errorOnList: const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'Could not load messages.',
        ),
      ),
      socketService: _ControllableSocketService(),
    );

    expect(find.text('Could not load messages.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('opening a chat marks its history as read', (tester) async {
    final repository = _FakeMessageRepository(
      initialMessages: [_message(id: 'm1', senderId: 'bob', body: 'Hi Alice')],
    );
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: _ControllableSocketService(),
    );

    expect(repository.markedReadChatIds, ['chat1']);
  });

  testWidgets(
    'sending a message (User A -> User B) posts it and shows it as sent',
    (tester) async {
      final repository = _FakeMessageRepository();
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      await tester.enterText(
        find.byType(TextField),
        'Hello Bob, this is Alice',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // What actually reached the "server" is ciphertext — the real
      // proof it's genuinely encrypted, not just re-displayed
      // plaintext, is that it decrypts back to the original.
      expect(repository.sentBodies, hasLength(1));
      expect(repository.sentBodies.single, isNot('Hello Bob, this is Alice'));
      expect(
        await _crypto.decryptText(_chatKey, repository.sentBodies.single),
        'Hello Bob, this is Alice',
      );
      expect(find.text('Hello Bob, this is Alice'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget); // "sent" tick
    },
  );

  testWidgets('a message shows a sending indicator before it resolves', (
    tester,
  ) async {
    final repository = _FakeMessageRepository(
      sendDelay: const Duration(milliseconds: 200),
    );
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: _ControllableSocketService(),
    );

    await tester.enterText(find.byType(TextField), 'On its way');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(); // let the optimistic "sending" message land

    expect(find.text('On its way'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing); // not resolved yet

    await tester.pump(const Duration(milliseconds: 250)); // past the fake delay
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets(
    'a message pushed over the socket (User B -> User A) appears without sending',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: socketService,
      );

      expect(find.text('No messages yet. Say hello!'), findsOneWidget);

      socketService.pushIncoming(
        _message(id: 'incoming-1', senderId: 'bob', body: 'Hi Alice!'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hi Alice!'), findsOneWidget);
      expect(find.text('No messages yet. Say hello!'), findsNothing);
    },
  );

  testWidgets('a socket echo of a message I just sent is not shown twice', (
    tester,
  ) async {
    final repository = _FakeMessageRepository();
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: socketService,
    );

    await tester.enterText(find.byType(TextField), 'Only once, please');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('Only once, please'), findsOneWidget);

    // The backend broadcasts every persisted message to the whole room,
    // sender included (see backend/src/controllers/message.controller.js)
    // — the client is expected to de-dupe by id.
    socketService.pushIncoming(
      _message(id: 'sent-1', senderId: _me.id, body: 'Only once, please'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Only once, please'), findsOneWidget);
  });

  testWidgets(
    'a failed send shows a failed status, and tapping it retries successfully',
    (tester) async {
      final repository = _FakeMessageRepository(
        errorOnSend: const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'Could not send message.',
        ),
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      await tester.enterText(find.byType(TextField), 'This will fail');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Persistent, visual failed state — not a transient snackbar.
      expect(find.text('This will fail'), findsOneWidget);
      expect(find.textContaining('Failed to send'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      repository.errorOnSend = null; // the network's back
      await tester.tap(find.text('This will fail'));
      await tester.pumpAndSettle();

      // The first attempt threw before ever reaching `sentBodies` — only
      // the retry lands here (same reasoning as the media version of
      // this test below).
      expect(repository.sentBodies, hasLength(1));
      expect(
        await _crypto.decryptText(_chatKey, repository.sentBodies.single),
        'This will fail',
      );
      expect(find.textContaining('Failed to send'), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
    },
  );

  testWidgets('a status push upgrades a sent message to delivered, then read', (
    tester,
  ) async {
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [
          _message(
            id: 'm1',
            senderId: _me.id,
            body: 'Seen this?',
            status: MessageStatus.sent,
          ),
        ],
      ),
      socketService: socketService,
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsNothing);

    socketService.pushStatus(
      const MessageStatusUpdate(
        chatId: 'chat1',
        messageIds: ['m1'],
        status: MessageStatus.delivered,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.done_all), findsOneWidget);

    socketService.pushStatus(
      const MessageStatusUpdate(
        chatId: 'chat1',
        messageIds: ['m1'],
        status: MessageStatus.read,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byIcon(Icons.done_all),
      findsOneWidget,
    ); // still the double-check icon
  });

  testWidgets('a status push for a different chat is ignored', (tester) async {
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [_message(id: 'm1', senderId: _me.id, body: 'hi')],
      ),
      socketService: socketService,
    );

    expect(find.byIcon(Icons.check), findsOneWidget);

    socketService.pushStatus(
      const MessageStatusUpdate(
        chatId: 'some-other-chat',
        messageIds: ['m1'],
        status: MessageStatus.read,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.check), findsOneWidget); // unchanged
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  testWidgets('a message for a different chat is ignored', (tester) async {
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(),
      socketService: socketService,
    );

    socketService.pushIncoming(
      Message(
        id: 'other-chat-1',
        chatId: 'some-other-chat',
        senderId: 'bob',
        type: 'text',
        body: 'Not for this thread',
        createdAt: DateTime(2026, 1, 1, 12),
        status: MessageStatus.sent,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Not for this thread'), findsNothing);
    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
  });

  // --- Typing indicators --------------------------------------------------

  testWidgets(
    'shows "typing…" while the other participant is typing, and hides it when they stop',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: socketService,
      );

      expect(find.text('typing…'), findsNothing);

      socketService.pushTyping(
        const TypingUpdate(chatId: 'chat1', userId: 'bob', isTyping: true),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('typing…'), findsOneWidget);

      socketService.pushTyping(
        const TypingUpdate(chatId: 'chat1', userId: 'bob', isTyping: false),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('typing…'), findsNothing);
    },
  );

  testWidgets(
    'the typing indicator auto-clears if no explicit stop event ever arrives',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: socketService,
      );

      socketService.pushTyping(
        const TypingUpdate(chatId: 'chat1', userId: 'bob', isTyping: true),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('typing…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5)); // the safety-net timeout
      expect(find.text('typing…'), findsNothing);
    },
  );

  testWidgets('a typing update for a different chat is ignored', (
    tester,
  ) async {
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(),
      socketService: socketService,
    );

    socketService.pushTyping(
      const TypingUpdate(
        chatId: 'some-other-chat',
        userId: 'bob',
        isTyping: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('typing…'), findsNothing);
  });

  testWidgets(
    'typing in the composer notifies the other side, then auto-stops after a pause',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: socketService,
      );

      await tester.enterText(find.byType(TextField), 'h');
      await tester.pump();
      expect(socketService.emittedTyping.length, 1);
      expect(socketService.emittedTyping.single.isTyping, true);

      // Still typing — already-typing state isn't re-announced on every
      // keystroke, only the pause timer resets.
      await tester.enterText(find.byType(TextField), 'he');
      await tester.pump();
      expect(socketService.emittedTyping.length, 1);

      await tester.pump(
        const Duration(seconds: 3),
      ); // the composer's pause timeout
      expect(socketService.emittedTyping.length, 2);
      expect(socketService.emittedTyping.last.isTyping, false);
    },
  );

  testWidgets(
    'clearing the composer stops typing immediately, without waiting out the pause',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: socketService,
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(socketService.emittedTyping.last.isTyping, true);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(socketService.emittedTyping.last.isTyping, false);
    },
  );

  testWidgets('sending a message stops typing immediately', (tester) async {
    final repository = _FakeMessageRepository();
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: socketService,
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(socketService.emittedTyping.last.isTyping, true);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(socketService.emittedTyping.last.isTyping, false);
  });

  // --- Message editing ------------------------------------------------

  testWidgets(
    'long-pressing my own sent message opens an edit dialog, pre-filled',
    (tester) async {
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(
          initialMessages: [
            _message(id: 'm1', senderId: _me.id, body: 'Original text'),
          ],
        ),
        socketService: _ControllableSocketService(),
      );

      await tester.longPress(find.text('Original text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit message'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Original text'), findsOneWidget);
    },
  );

  testWidgets('long-pressing a message that is not mine does nothing', (
    tester,
  ) async {
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: 'bob', body: "Bob's message"),
        ],
      ),
      socketService: _ControllableSocketService(),
    );

    await tester.longPress(find.text("Bob's message"));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Edit message'), findsNothing);
  });

  testWidgets(
    'saving an edit updates the message body and shows the edited indicator',
    (tester) async {
      final repository = _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: _me.id, body: 'Original text'),
        ],
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      await tester.longPress(find.text('Original text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Original text'),
        'Corrected text',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repository.editedMessages, hasLength(1));
      expect(repository.editedMessages.single.$1, 'm1');
      expect(
        await _crypto.decryptText(
          _chatKey,
          repository.editedMessages.single.$2,
        ),
        'Corrected text',
      );
      expect(find.text('Edit message'), findsNothing); // dialog closed
      expect(find.text('Corrected text'), findsOneWidget);
      expect(find.text('Original text'), findsNothing);
      expect(find.text('edited'), findsOneWidget);
    },
  );

  testWidgets('canceling the edit dialog leaves the message unchanged', (
    tester,
  ) async {
    final repository = _FakeMessageRepository(
      initialMessages: [
        _message(id: 'm1', senderId: _me.id, body: 'Original text'),
      ],
    );
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: _ControllableSocketService(),
    );

    await tester.longPress(find.text('Original text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Original text'),
      'Never saved',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.editedMessages, isEmpty);
    expect(find.text('Original text'), findsOneWidget);
    expect(find.text('edited'), findsNothing);
  });

  testWidgets(
    'a rejected edit (e.g. not the sender — authorization) shows an inline error and keeps the dialog open',
    (tester) async {
      final repository = _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: _me.id, body: 'Original text'),
        ],
        errorOnEdit: const ApiException(
          statusCode: 403,
          code: 'FORBIDDEN',
          message: 'You can only edit your own messages.',
        ),
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      await tester.longPress(find.text('Original text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Original text'),
        'Nice try',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Edit message'), findsOneWidget); // still open
      expect(find.text('You can only edit your own messages.'), findsOneWidget);
      expect(
        find.text('Original text'),
        findsOneWidget,
      ); // unchanged in the thread
    },
  );

  testWidgets(
    'a live "message:edited" push updates the bubble for the other participant',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(
          initialMessages: [
            _message(id: 'm1', senderId: 'bob', body: "Bob's original"),
          ],
        ),
        socketService: socketService,
      );

      expect(find.text("Bob's original"), findsOneWidget);

      socketService.pushEdited(
        Message(
          id: 'm1',
          chatId: 'chat1',
          senderId: 'bob',
          type: 'text',
          body: _encryptedBody["Bob's corrected message"]!,
          createdAt: DateTime(2026, 1, 1, 12),
          editedAt: DateTime(2026, 1, 1, 12, 5),
          status: MessageStatus.sent,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Bob's original"), findsNothing);
      expect(find.text("Bob's corrected message"), findsOneWidget);
      expect(find.text('edited'), findsOneWidget);
    },
  );

  testWidgets('a "message:edited" push for a different chat is ignored', (
    tester,
  ) async {
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: 'bob', body: 'Untouched'),
        ],
      ),
      socketService: socketService,
    );

    socketService.pushEdited(
      Message(
        id: 'm1',
        chatId: 'some-other-chat',
        senderId: 'bob',
        type: 'text',
        body: 'Should not apply',
        createdAt: DateTime(2026, 1, 1, 12),
        editedAt: DateTime(2026, 1, 1, 12, 5),
        status: MessageStatus.sent,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Untouched'), findsOneWidget);
    expect(find.text('Should not apply'), findsNothing);
  });

  // --- Message deletion -----------------------------------------------

  testWidgets('long-pressing my own message offers Edit and Delete', (
    tester,
  ) async {
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: _me.id, body: 'Original text'),
        ],
      ),
      socketService: _ControllableSocketService(),
    );

    await tester.longPress(find.text('Original text'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets(
    'canceling the delete confirmation leaves the message untouched',
    (tester) async {
      final repository = _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: _me.id, body: 'Original text'),
        ],
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      await tester.longPress(find.text('Original text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete message?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deletedMessageIds, isEmpty);
      expect(find.text('Original text'), findsOneWidget);
      expect(find.text('This message was deleted'), findsNothing);
    },
  );

  testWidgets('confirming delete shows the tombstone for the sender', (
    tester,
  ) async {
    final repository = _FakeMessageRepository(
      initialMessages: [
        _message(id: 'm1', senderId: _me.id, body: 'Original text'),
      ],
    );
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: _ControllableSocketService(),
    );

    await tester.longPress(find.text('Original text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete message?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deletedMessageIds, ['m1']);
    expect(find.text('Original text'), findsNothing);
    expect(find.text('This message was deleted'), findsOneWidget);
  });

  testWidgets(
    'a rejected delete shows an error and leaves the message intact',
    (tester) async {
      final repository = _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: _me.id, body: 'Original text'),
        ],
        errorOnDelete: const ApiException(
          statusCode: 403,
          code: 'FORBIDDEN',
          message: 'You can only delete your own messages.',
        ),
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      await tester.longPress(find.text('Original text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text('You can only delete your own messages.'),
        findsOneWidget,
      );
      expect(find.text('Original text'), findsOneWidget); // unchanged
      expect(find.text('This message was deleted'), findsNothing);
    },
  );

  testWidgets('a deleted message is no longer long-press actionable', (
    tester,
  ) async {
    final repository = _FakeMessageRepository(
      initialMessages: [
        _message(id: 'm1', senderId: _me.id, body: 'Original text'),
      ],
    );
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: _ControllableSocketService(),
    );

    await tester.longPress(find.text('Original text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('This message was deleted'), findsOneWidget);

    await tester.longPress(find.text('This message was deleted'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete message?'), findsNothing);
  });

  testWidgets(
    'a live "message:deleted" push shows the tombstone for the receiver (User B\'s view)',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(
          initialMessages: [
            _message(id: 'm1', senderId: 'bob', body: "Bob's message"),
          ],
        ),
        socketService: socketService,
      );

      expect(find.text("Bob's message"), findsOneWidget);

      socketService.pushDeleted(
        Message(
          id: 'm1',
          chatId: 'chat1',
          senderId: 'bob',
          type: 'text',
          createdAt: DateTime(2026, 1, 1, 12),
          deletedAt: DateTime(2026, 1, 1, 12, 5),
          status: MessageStatus.sent,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text("Bob's message"), findsNothing);
      expect(find.text('This message was deleted'), findsOneWidget);
    },
  );

  testWidgets('a "message:deleted" push for a different chat is ignored', (
    tester,
  ) async {
    final socketService = _ControllableSocketService();
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(
        initialMessages: [
          _message(id: 'm1', senderId: 'bob', body: 'Untouched'),
        ],
      ),
      socketService: socketService,
    );

    socketService.pushDeleted(
      Message(
        id: 'm1',
        chatId: 'some-other-chat',
        senderId: 'bob',
        type: 'text',
        createdAt: DateTime(2026, 1, 1, 12),
        deletedAt: DateTime(2026, 1, 1, 12, 5),
        status: MessageStatus.sent,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Untouched'), findsOneWidget);
    expect(find.text('This message was deleted'), findsNothing);
  });

  // --- Image & video messages ----------------------------------------------
  //
  // Same bypass as avatar_upload_flow_test.dart: image_picker and the
  // native compression plugins aren't mockable via Riverpod overrides, so
  // these tests skip straight past `_pickAttachment` and drive
  // `ChatDetailController.sendImage`/`sendVideo`/`retryMedia` directly,
  // with an already-"compressed" local path standing in for whatever the
  // real picker+compression flow would have produced.

  testWidgets(
    'sending an image (User A -> User B) resolves to the decrypted uploaded image',
    (tester) async {
      final repository = _FakeMessageRepository();
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );
      final originalBytes = Uint8List.fromList(_validPngBytes);

      final element = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(element);
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .sendImage(originalBytes);
      await tester
          .pumpAndSettle(); // let the fetch+decrypt FutureBuilder resolve

      // What was actually uploaded is ciphertext — decrypting it back
      // with the real chat key recovers the exact original bytes.
      expect(repository.sentMediaBytes, hasLength(1));
      expect(
        await _crypto.decryptBytes(_chatKey, repository.sentMediaBytes.single),
        originalBytes,
      );
      final networkImage = tester.widget<Image>(find.byType(Image));
      expect(
        (networkImage.image as MemoryImage).bytes,
        Uint8List.fromList(originalBytes),
      );
      expect(find.byIcon(Icons.check), findsOneWidget); // "sent" tick
    },
  );

  testWidgets(
    'sending a video (User A -> User B) posts it and resolves to sent',
    (tester) async {
      final repository = _FakeMessageRepository();
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );
      final element = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(element);
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .sendVideo(Uint8List.fromList([9, 9, 9]));
      await tester.pump();
      await tester.pump();

      expect(repository.sentMediaBytes, hasLength(1));
      expect(
        await _crypto.decryptBytes(_chatKey, repository.sentMediaBytes.single),
        [9, 9, 9],
      );
      expect(find.byIcon(Icons.check), findsOneWidget); // "sent" tick
    },
  );

  testWidgets(
    'sending a voice message (User A -> User B) posts it and resolves to sent',
    (tester) async {
      final repository = _FakeMessageRepository();
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );

      final element = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(element);
      // Same `AudioRecorderService`-bypass reasoning as image/video above:
      // `record` isn't mockable via Riverpod overrides either, so this
      // drives `ChatDetailController.sendAudio` directly with bytes
      // standing in for whatever a real recording would have produced.
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .sendAudio(Uint8List.fromList([4, 8, 15, 16, 23, 42]));
      await tester.pump();
      await tester.pump();

      expect(repository.sentMediaBytes, hasLength(1));
      expect(
        await _crypto.decryptBytes(_chatKey, repository.sentMediaBytes.single),
        [4, 8, 15, 16, 23, 42],
      );
      expect(find.byIcon(Icons.check), findsOneWidget); // "sent" tick
    },
  );

  testWidgets(
    'a failed voice message send shows a failed status, and retrying resends the same local file',
    (tester) async {
      final repository = _FakeMessageRepository(
        errorOnSendMedia: const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'Could not send voice message.',
        ),
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );
      final element = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(element);
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .sendAudio(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to send'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsWidgets);

      repository.errorOnSendMedia = null; // the network's back
      final failedId = container
          .read(chatDetailControllerProvider('chat1'))
          .value!
          .single
          .id;
      // No path/bytes to pass here — `retryMedia` re-sends the bytes
      // already sitting on the failed message's own `localBytes` (see
      // `Message.localBytes`'s doc comment), same ones as the original
      // attempt above.
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .retryMedia(failedId);
      await tester.pump();
      await tester.pump();

      expect(repository.sentMediaBytes, hasLength(1));
      expect(
        await _crypto.decryptBytes(_chatKey, repository.sentMediaBytes.single),
        [1, 2, 3],
      );
      expect(find.byIcon(Icons.check), findsOneWidget); // "sent" tick
    },
  );

  testWidgets(
    'a failed image send shows a failed status, and retrying resends the same local file',
    (tester) async {
      final repository = _FakeMessageRepository(
        errorOnSendMedia: const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'Could not send image.',
        ),
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: _ControllableSocketService(),
      );
      final element = tester.element(find.byType(Scaffold).first);
      final container = ProviderScope.containerOf(element);
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .sendImage(Uint8List.fromList([7, 7, 7]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to send'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final failedImage = tester.widget<Image>(find.byType(Image));
      expect(
        (failedImage.image as MemoryImage).bytes,
        Uint8List.fromList([7, 7, 7]),
      );

      repository.errorOnSendMedia = null; // the network's back
      // Retries via the controller directly rather than tapping the
      // bubble — the tap → onRetry wiring itself is already covered
      // generically by the analogous text-message retry test above
      // (both types share the same `onRetry` plumbing in
      // chat_detail_screen.dart); what matters here is specifically
      // "does retry resend the same bytes".
      final failedId = container
          .read(chatDetailControllerProvider('chat1'))
          .value!
          .firstWhere((m) => m.status == MessageStatus.failed)
          .id;
      await container
          .read(chatDetailControllerProvider('chat1').notifier)
          .retryMedia(failedId);
      await tester.pumpAndSettle();

      // The first attempt threw before ever reaching `sentMediaBytes` (see
      // the fake's `sendMediaMessage` above) — only the retry lands here.
      expect(repository.sentMediaBytes, hasLength(1));
      expect(
        await _crypto.decryptBytes(_chatKey, repository.sentMediaBytes.single),
        [7, 7, 7],
      );
      expect(find.textContaining('Failed to send'), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
    },
  );

  testWidgets(
    'an image pushed over the socket (User B -> User A) displays via decrypted bytes',
    (tester) async {
      final socketService = _ControllableSocketService();
      final repository = _FakeMessageRepository();
      const url = '/uploads/messages/bob-photo.enc';
      repository.mediaStore[url] = await _crypto.encryptBytes(
        _chatKey,
        _validPngBytes,
      );
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: socketService,
      );

      socketService.pushIncoming(
        Message(
          id: 'incoming-image-1',
          chatId: 'chat1',
          senderId: 'bob',
          type: 'image',
          mediaUrl: url,
          createdAt: DateTime(2026, 1, 1, 12),
          status: MessageStatus.sent,
        ),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as MemoryImage).bytes,
        Uint8List.fromList(_validPngBytes),
      );
    },
  );

  testWidgets(
    'a video pushed over the socket (User B -> User A) appears in the thread',
    (tester) async {
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: socketService,
      );

      expect(find.text('No messages yet. Say hello!'), findsOneWidget);

      socketService.pushIncoming(
        Message(
          id: 'incoming-video-1',
          chatId: 'chat1',
          senderId: 'bob',
          type: 'video',
          mediaUrl: '/uploads/messages/bob-clip.mp4',
          createdAt: DateTime(2026, 1, 1, 12),
          status: MessageStatus.sent,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No messages yet. Say hello!'), findsNothing);
      // No plugin backs video_player in a widget test, so the player
      // itself never finishes initializing (and this message's mediaUrl
      // isn't in `mediaStore` either, so decryption never even gets that
      // far) — what matters here is that the message landed in the
      // thread and rendering it didn't crash.
    },
  );

  testWidgets(
    'a voice message pushed over the socket (User B -> User A) appears in the '
    'thread and is ready to play',
    (tester) async {
      final repository = _FakeMessageRepository();
      const url = '/uploads/messages/bob-voice.m4a';
      // Unlike video, audio's fetch+decrypt path needs no platform
      // channel at all — `audioplayers` only touches one once playback
      // actually *starts*, not to load a `BytesSource`. Pre-populating
      // this means the assertion below genuinely proves the received
      // ciphertext was downloaded and decrypted, not just that
      // rendering the row didn't crash.
      repository.mediaStore[url] = await _crypto.encryptBytes(_chatKey, [
        4,
        8,
        15,
        16,
        23,
        42,
      ]);
      final socketService = _ControllableSocketService();
      await _pumpChatDetail(
        tester,
        messageRepository: repository,
        socketService: socketService,
      );

      expect(find.text('No messages yet. Say hello!'), findsOneWidget);

      socketService.pushIncoming(
        Message(
          id: 'incoming-audio-1',
          chatId: 'chat1',
          senderId: 'bob',
          type: 'audio',
          mediaUrl: url,
          createdAt: DateTime(2026, 1, 1, 12),
          status: MessageStatus.sent,
        ),
      );
      await tester.pumpAndSettle(); // let the fetch+decrypt resolve

      expect(find.text('No messages yet. Say hello!'), findsNothing);
      expect(find.byIcon(Icons.play_circle), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    },
  );

  testWidgets('Edit is not offered for an image message, only Delete', (
    tester,
  ) async {
    const url = '/uploads/messages/my-photo.enc';
    final repository = _FakeMessageRepository(
      initialMessages: [
        Message(
          id: 'm1',
          chatId: 'chat1',
          senderId: _me.id,
          type: 'image',
          mediaUrl: url,
          createdAt: DateTime(2026, 1, 1, 12),
          status: MessageStatus.sent,
        ),
      ],
    );
    repository.mediaStore[url] = await _crypto.encryptBytes(
      _chatKey,
      _validPngBytes,
    );
    await _pumpChatDetail(
      tester,
      messageRepository: repository,
      socketService: _ControllableSocketService(),
    );

    await tester.longPress(
      find.ancestor(of: find.byType(Image), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
  });

  // --- Per-chat notification muting -----------------------------------

  testWidgets(
    'the app bar shows an unmuted bell for a chat that is not muted, and '
    'tapping it mutes',
    (tester) async {
      final chatRepository = _FakeChatRepository(_bobPublicKey);
      await _pumpChatDetail(
        tester,
        messageRepository: _FakeMessageRepository(),
        socketService: _ControllableSocketService(),
        chatRepository: chatRepository,
      );

      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off), findsNothing);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(chatRepository.muteCalls, ['chat1']);
      expect(find.byIcon(Icons.notifications_off), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsNothing);
    },
  );

  testWidgets('the app bar shows a muted bell for an already-muted chat, and '
      'tapping it unmutes', (tester) async {
    final chatRepository = _FakeChatRepository(
      _bobPublicKey,
      mutedAt: DateTime(2026, 1, 1),
    );
    await _pumpChatDetail(
      tester,
      messageRepository: _FakeMessageRepository(),
      socketService: _ControllableSocketService(),
      chatRepository: chatRepository,
    );

    expect(find.byIcon(Icons.notifications_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_off));
    await tester.pumpAndSettle();

    expect(chatRepository.unmuteCalls, ['chat1']);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });
}
