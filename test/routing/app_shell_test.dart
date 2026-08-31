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
const _carol = ChatParticipant(
  id: 'carol',
  username: 'carol',
  displayName: 'carol',
);

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

  final _chatBob = Chat(
    id: 'c1',
    isGroup: false,
    createdAt: DateTime(2026, 1, 1),
    otherParticipant: _bob,
  );
  final _chatCarol = Chat(
    id: 'c2',
    isGroup: false,
    createdAt: DateTime(2026, 1, 1),
    otherParticipant: _carol,
  );

  @override
  Future<List<Chat>> listChats({required bool archived}) async =>
      archived ? const [] : [_chatBob, _chatCarol];

  @override
  Future<Chat> getChat(String chatId) async =>
      chatId == _chatCarol.id ? _chatCarol : _chatBob;
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

Future<void> _pumpDesktopApp(
  WidgetTester tester, {
  FakeSocketService? socketService,
}) async {
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
        socketServiceProvider.overrideWithValue(
          socketService ?? FakeSocketService(),
        ),
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

  // --- Phase 11: multiple simultaneous chat panels --------------------

  testWidgets(
    'opening a second chat keeps the first one open alongside it, not '
    'replaced by it',
    (tester) async {
      await _pumpDesktopApp(tester);

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('carol'));
      await tester.pumpAndSettle();

      // Two open panels — each app bar's mute button is unique to
      // `ChatDetailScreen`, so its count is exactly "how many panels are
      // open" regardless of what else is on screen.
      expect(find.byIcon(Icons.notifications_none), findsNWidgets(2));
      // The chat list pane is still visible alongside both.
      expect(find.text('Select a chat to start messaging'), findsNothing);
    },
  );

  testWidgets(
    'each open panel is its own independent chat, not two views of the '
    'same one',
    (tester) async {
      await _pumpDesktopApp(tester);

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('carol'));
      await tester.pumpAndSettle();

      // "bob"/"carol" each now appear twice — once as their own list
      // tile, once as their own panel's app-bar title.
      expect(find.text('bob'), findsNWidgets(2));
      expect(find.text('carol'), findsNWidgets(2));
    },
  );

  testWidgets('closing one panel leaves the other open and untouched', (
    tester,
  ) async {
    await _pumpDesktopApp(tester);

    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_none), findsNWidgets(2));

    // Panels render left to right in the order they were opened —
    // bob's was opened first, so its close button is the first match.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    // carol's panel is the one still standing.
    expect(find.text('carol'), findsNWidgets(2));
    // The chat list itself is unaffected by closing a panel — bob is
    // still a selectable tile, just with no open panel of his own any
    // more.
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('closing the only open panel returns to the no-chat-selected '
      'placeholder', (tester) async {
    await _pumpDesktopApp(tester);

    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();
    expect(find.text('Select a chat to start messaging'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Select a chat to start messaging'), findsOneWidget);
  });

  testWidgets(
    're-selecting an already-open chat brings it into view rather than '
    'opening a second copy of it',
    (tester) async {
      await _pumpDesktopApp(tester);

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('carol'));
      await tester.pumpAndSettle();
      // Both panels are open now, so "bob" matches twice (the list tile
      // and bob's own panel's app bar title) — `.first` is the list
      // tile, since the list pane is built before the panels.
      await tester.tap(find.text('bob').first);
      await tester.pumpAndSettle();

      // Still exactly two panels — tapping bob again didn't add a
      // duplicate.
      expect(find.byIcon(Icons.notifications_none), findsNWidgets(2));
    },
  );

  // --- Phase 12: connection status is visible on every desktop route --

  testWidgets(
    'a dropped realtime connection is visible on the Profile screen too, '
    'not just the chat screens',
    (tester) async {
      await _pumpDesktopApp(
        tester,
        socketService: FakeSocketService(connected: false),
      );

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsWidgets);
      expect(find.text('No connection — reconnecting…'), findsOneWidget);
    },
  );

  testWidgets('the connection banner disappears once the socket reconnects', (
    tester,
  ) async {
    final socketService = FakeSocketService(connected: false);
    await _pumpDesktopApp(tester, socketService: socketService);

    expect(find.text('No connection — reconnecting…'), findsOneWidget);

    socketService.setConnected(true);
    await tester.pumpAndSettle();

    expect(find.text('No connection — reconnecting…'), findsNothing);
  });
}
