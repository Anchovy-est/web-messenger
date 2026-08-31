import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/features/chats/data/message_repository.dart';
import 'package:mobile_messenger/features/chats/presentation/chat_detail_screen.dart';
import 'package:mobile_messenger/features/chats/presentation/chat_list_screen.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/models/message.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';

import '../../support/fake_secure_storage_service.dart';
import '../../support/fake_socket_service.dart';

const _bob = ChatParticipant(id: 'bob', username: 'bob', displayName: 'bob');
const _carol = ChatParticipant(
  id: 'carol',
  username: 'carol',
  displayName: 'carol',
);
final _now = DateTime(2026, 1, 1, 12);

Chat _chat({
  required String id,
  ChatParticipant otherParticipant = _bob,
  LastMessagePreview? lastMessage,
  DateTime? archivedAt,
  DateTime? mutedAt,
}) {
  return Chat(
    id: id,
    isGroup: false,
    createdAt: _now,
    archivedAt: archivedAt,
    mutedAt: mutedAt,
    otherParticipant: otherParticipant,
    lastMessage: lastMessage,
  );
}

/// Records archive/unarchive calls and serves independently-configurable
/// active/archived lists — mirrors the shape the real backend enforces
/// (archiving is per-user, so the two lists never overlap).
class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository({
    this.active = const [],
    this.archived = const [],
    this.errorOnActive,
    this.errorOnArchived,
  }) : super(ApiClient());

  final List<Chat> active;
  final List<Chat> archived;
  final ApiException? errorOnActive;
  final ApiException? errorOnArchived;
  final List<String> archivedIds = [];
  final List<String> unarchivedIds = [];

  @override
  Future<List<Chat>> listChats({required bool archived}) async {
    if (archived) {
      if (errorOnArchived != null) throw errorOnArchived!;
      return this.archived;
    }
    if (errorOnActive != null) throw errorOnActive!;
    return active;
  }

  @override
  Future<Chat> archive(String chatId) async {
    archivedIds.add(chatId);
    return active.firstWhere((c) => c.id == chatId);
  }

  @override
  Future<Chat> unarchive(String chatId) async {
    unarchivedIds.add(chatId);
    return archived.firstWhere((c) => c.id == chatId);
  }

  // `ChatDetailController` fetches the chat once at startup for the
  // other participant's public key — without this override that falls
  // through to a real network call, which never resolves in a test and
  // hangs `pumpAndSettle()`.
  @override
  Future<Chat> getChat(String chatId) async {
    return [...active, ...archived].firstWhere((c) => c.id == chatId);
  }
}

/// The "open a chat" test below only needs the detail screen to render
/// without hitting a real network call — its own content is covered by
/// chat_detail_flow_test.dart.
class _FakeMessageRepository extends MessageRepository {
  _FakeMessageRepository() : super(ApiClient());

  @override
  Future<List<Message>> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async => const [];

  @override
  Future<void> markDelivered(String chatId) async {}

  @override
  Future<void> markRead(String chatId) async {}
}

Future<void> _pumpChatList(
  WidgetTester tester, {
  required _FakeChatRepository repository,
  FakeSocketService? socket,
}) async {
  // A router scoped to just what the chat list touches — the real
  // app's router also gates on session status, not this file's concern.
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatListScreen()),
      GoRoute(
        path: '/chats/:id',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ChatDetailScreen(
            chatId: state.pathParameters['id']!,
            title: extra?['title'] as String?,
            avatarUrl: extra?['avatarUrl'] as String?,
          );
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // No identity key configured here — this file is about
        // list/sort/archive behavior, not encryption, so
        // `ChatListController` short-circuits decryption and shows
        // `lastMessage.body` as given, letting fixtures stay plain
        // text.
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(identityPrivateKey: null),
        ),
        chatRepositoryProvider.overrideWithValue(repository),
        messageRepositoryProvider.overrideWithValue(_FakeMessageRepository()),
        socketServiceProvider.overrideWithValue(socket ?? FakeSocketService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows active chats in the order the backend returns (sorted server-side)',
    (tester) async {
      final repository = _FakeChatRepository(
        active: [
          _chat(
            id: 'c1',
            otherParticipant: _bob,
            lastMessage: LastMessagePreview(
              id: 'm1',
              type: 'text',
              body: 'Hey there',
              senderId: 'bob',
              createdAt: _now,
            ),
          ),
          _chat(id: 'c2', otherParticipant: _carol),
        ],
      );
      await _pumpChatList(tester, repository: repository);

      final tiles = find.byType(ListTile);
      expect(tiles, findsNWidgets(2));
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('Hey there'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
      expect(
        find.text('No messages yet.'),
        findsOneWidget,
      ); // c2 has no last message
    },
  );

  testWidgets('shows the empty state when there are no active chats', (
    tester,
  ) async {
    await _pumpChatList(tester, repository: _FakeChatRepository());

    expect(find.textContaining('No chats yet.'), findsOneWidget);
  });

  testWidgets(
    'an empty active chat list still offers pull-to-refresh, not just a '
    'full app restart, e.g. right after accepting an invitation',
    (tester) async {
      await _pumpChatList(tester, repository: _FakeChatRepository());

      expect(find.textContaining('No chats yet.'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Actually drag to confirm the empty state is inside a scrollable
      // RefreshIndicator can detect, not just present but inert.
      await tester.fling(
        find.textContaining('No chats yet.'),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('shows an error with retry when loading active chats fails', (
    tester,
  ) async {
    await _pumpChatList(
      tester,
      repository: _FakeChatRepository(
        errorOnActive: const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'Something went wrong.',
        ),
      ),
    );

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('shows an error with retry when loading archived chats fails', (
    tester,
  ) async {
    await _pumpChatList(
      tester,
      repository: _FakeChatRepository(
        errorOnArchived: const ApiException(
          statusCode: 500,
          code: 'INTERNAL_ERROR',
          message: 'Could not load archived chats.',
        ),
      ),
    );

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load archived chats.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('archiving a chat removes it from the Active tab', (
    tester,
  ) async {
    final repository = _FakeChatRepository(
      active: [_chat(id: 'c1', otherParticipant: _bob)],
    );
    await _pumpChatList(tester, repository: repository);

    expect(find.text('bob'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pumpAndSettle();

    expect(repository.archivedIds, ['c1']);
    expect(find.text('bob'), findsNothing);
    expect(find.textContaining('No chats yet.'), findsOneWidget);
  });

  testWidgets(
    'the Archived tab shows archived chats with an unarchive action',
    (tester) async {
      final repository = _FakeChatRepository(
        archived: [_chat(id: 'c1', otherParticipant: _bob, archivedAt: _now)],
      );
      await _pumpChatList(tester, repository: repository);

      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
      expect(find.byIcon(Icons.unarchive_outlined), findsOneWidget);
    },
  );

  testWidgets('unarchiving a chat removes it from the Archived tab', (
    tester,
  ) async {
    final repository = _FakeChatRepository(
      archived: [_chat(id: 'c1', otherParticipant: _bob, archivedAt: _now)],
    );
    await _pumpChatList(tester, repository: repository);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.unarchive_outlined));
    await tester.pumpAndSettle();

    expect(repository.unarchivedIds, ['c1']);
    expect(find.text('bob'), findsNothing);
    expect(find.text('No archived chats.'), findsOneWidget);
  });

  testWidgets('opening a chat navigates to the chat detail screen', (
    tester,
  ) async {
    final repository = _FakeChatRepository(
      active: [_chat(id: 'c1', otherParticipant: _bob)],
    );
    await _pumpChatList(tester, repository: repository);

    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();

    // Landed on the real chat detail screen for the right chat — its
    // own content is covered by chat_detail_flow_test.dart.
    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
    // The detail screen's own AppBar carries over the chat's display name.
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('shows nothing extra while the realtime connection is up', (
    tester,
  ) async {
    await _pumpChatList(tester, repository: _FakeChatRepository());

    expect(find.textContaining('No connection'), findsNothing);
  });

  testWidgets(
    'shows a banner when the realtime connection drops, and hides it again '
    'once it reconnects',
    (tester) async {
      final socket = FakeSocketService(connected: false);
      await _pumpChatList(
        tester,
        repository: _FakeChatRepository(),
        socket: socket,
      );

      expect(find.textContaining('No connection'), findsOneWidget);

      socket.setConnected(true);
      await tester.pumpAndSettle();

      expect(find.textContaining('No connection'), findsNothing);
    },
  );

  testWidgets('a muted chat shows a muted indicator; an unmuted one does not', (
    tester,
  ) async {
    final repository = _FakeChatRepository(
      active: [
        _chat(id: 'c1', otherParticipant: _bob, mutedAt: _now),
        _chat(id: 'c2', otherParticipant: _carol),
      ],
    );
    await _pumpChatList(tester, repository: repository);

    final bobTile = find.ancestor(
      of: find.text('bob'),
      matching: find.byType(ListTile),
    );
    final carolTile = find.ancestor(
      of: find.text('carol'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: bobTile,
        matching: find.byIcon(Icons.notifications_off),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: carolTile,
        matching: find.byIcon(Icons.notifications_off),
      ),
      findsNothing,
    );
  });
}
