import 'package:flutter/material.dart';
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

import '../support/fake_secure_storage_service.dart';
import '../support/fake_socket_service.dart';

const _me = User(
  id: 'u1',
  username: 'annab',
  email: 'anna@example.com',
  displayName: 'Anna',
  emailVerified: true,
);

const _bob = ChatParticipant(id: 'bob', username: 'bob', displayName: 'bob');

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(ApiClient());

  @override
  Future<User> fetchCurrentUser() async => _me;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async => const LoginResult(
    user: _me,
    accessToken: 'access',
    refreshToken: 'refresh',
  );
}

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(ApiClient());

  final _chat = Chat(
    id: 'c1',
    isGroup: false,
    createdAt: DateTime(2026, 1, 1),
    otherParticipant: _bob,
  );

  @override
  Future<List<Chat>> listChats({required bool archived}) async =>
      archived ? const [] : [_chat];

  @override
  Future<Chat> getChat(String chatId) async => _chat;
}

/// Enough of [MessageRepository] for `ChatDetailScreen` to mount cleanly
/// — its own content is covered by chat_detail_flow_test.dart; this test
/// is only about which panes the desktop shell shows alongside it.
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

Future<void> _pumpDesktopApp(WidgetTester tester) async {
  // Wider than `Breakpoints.mediumMax` — the "expanded" desktop window
  // size class, sidebar shown with labels.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
        messageRepositoryProvider.overrideWithValue(_FakeMessageRepository()),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
      child: const MessengerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a desktop-width window shows a persistent sidebar and no full-screen '
    'chat-list app bar',
    (tester) async {
      await _pumpDesktopApp(tester);

      expect(find.byType(NavigationRail), findsOneWidget);
      // The mobile `ChatListScreen`'s own app bar title never renders —
      // the desktop shell replaces that chrome with the sidebar + panes.
      expect(find.text('Mobile Messenger'), findsNothing);
      // The chat list pane itself is still there, sidebar or not.
      expect(find.text('bob'), findsOneWidget);
    },
  );

  testWidgets('with no chat open, the desktop shell shows a placeholder in the '
      'detail pane instead of an empty screen', (tester) async {
    await _pumpDesktopApp(tester);

    expect(find.text('Select a chat to start messaging'), findsOneWidget);
  });

  testWidgets(
    'selecting a chat on desktop shows its detail pane while the chat '
    'list pane stays visible alongside it (master-detail, not a swap)',
    (tester) async {
      await _pumpDesktopApp(tester);

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      // The detail pane opened...
      expect(find.text('No messages yet. Say hello!'), findsOneWidget);
      // ...without the list pane (still showing "bob"'s tile) disappearing
      // the way a mobile push navigation would replace it.
      expect(find.text('bob'), findsWidgets);
      expect(find.text('Select a chat to start messaging'), findsNothing);
    },
  );

  testWidgets('the Search sidebar destination opens SearchScreen as a desktop '
      'dialog rather than replacing the chat list', (tester) async {
    await _pumpDesktopApp(tester);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.text('Search for someone by username or email'),
      findsOneWidget,
    );
    // The chat list is still there, underneath the dialog.
    expect(find.text('bob'), findsOneWidget);
  });
}
