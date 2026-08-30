import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/features/chats/data/message_repository.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/models/message.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';

import 'support/fake_secure_storage_service.dart';
import 'support/fake_socket_service.dart';

const _fakeUser = User(
  id: 'u1',
  username: 'annab',
  email: 'anna@example.com',
  displayName: 'Anna',
  emailVerified: true,
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(ApiClient());

  @override
  Future<User> fetchCurrentUser() async => _fakeUser;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    return const LoginResult(
      user: _fakeUser,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }
}

/// Enough of [ChatRepository] for [ChatDetailScreen] to mount without
/// hitting the real (unmocked-in-tests) network — its own content isn't
/// what this test is about, only "did tapping a notification land here
/// at all, for the right chat id".
class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(ApiClient());

  @override
  Future<List<Chat>> listChats({required bool archived}) async => const [];

  @override
  Future<Chat> getChat(String chatId) async {
    return Chat(id: chatId, isGroup: false, createdAt: DateTime(2026, 1, 1));
  }
}

class _FakeMessageRepository extends MessageRepository {
  _FakeMessageRepository() : super(ApiClient());

  @override
  Future<List<Message>> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async => const [];

  @override
  Future<void> markRead(String chatId) async {}
}

void main() {
  testWidgets('tapping a message notification opens the correct chat', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'stored-access-token'),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
        messageRepositoryProvider.overrideWithValue(_FakeMessageRepository()),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MessengerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No chats yet.'), findsOneWidget);

    // Simulates what a real tap does: `PushNotificationService`'s
    // `chatIdToOpen` stream fires — real taps only ever reach it via
    // `firebase_messaging`/`flutter_local_notifications` callbacks,
    // neither of which resolves against a real plugin here (see
    // `debugEmitChatIdToOpen`'s own doc comment).
    container
        .read(pushNotificationServiceProvider)
        .debugEmitChatIdToOpen('chat-from-notification');
    await tester.pumpAndSettle();

    // Landed on the chat detail screen for exactly that chat — not the
    // chat list, not some other chat.
    expect(find.textContaining('No chats yet.'), findsNothing);
    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
  });
}
