import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/invitations/data/invitation_providers.dart';
import 'package:mobile_messenger/features/invitations/data/invitation_repository.dart';
import 'package:mobile_messenger/features/search/data/search_providers.dart';
import 'package:mobile_messenger/features/search/data/search_repository.dart';
import 'package:mobile_messenger/features/search/presentation/search_screen.dart';
import 'package:mobile_messenger/models/invitation.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/services/api_client.dart';

const _bob = User(
  id: 'bob',
  username: 'bob',
  email: 'bob@example.com',
  displayName: 'bob',
  emailVerified: false,
);

class _FakeSearchRepository extends SearchRepository {
  _FakeSearchRepository() : super(ApiClient());

  @override
  Future<List<User>> searchUsers(String query) async => [_bob];
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository({this.errorToThrow}) : super(ApiClient());

  final ApiException? errorToThrow;
  String? lastInviteeId;

  @override
  Future<Invitation> sendInvitation(String inviteeId) async {
    lastInviteeId = inviteeId;
    if (errorToThrow != null) throw errorToThrow!;
    return Invitation(
      id: 'inv1',
      chatId: 'chat1',
      status: InvitationStatus.pending,
      createdAt: DateTime(2026, 1, 1),
      inviter: const InvitationParticipant(
        id: 'me',
        username: 'me',
        displayName: 'me',
      ),
      invitee: const InvitationParticipant(
        id: 'bob',
        username: 'bob',
        displayName: 'bob',
      ),
    );
  }
}

Future<_FakeInvitationRepository> _pumpSearchWithResult(
  WidgetTester tester, {
  ApiException? invitationError,
}) async {
  final invitationRepository = _FakeInvitationRepository(
    errorToThrow: invitationError,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(_FakeSearchRepository()),
        invitationRepositoryProvider.overrideWithValue(invitationRepository),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.enterText(find.byType(TextField), 'bob');
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  return invitationRepository;
}

void main() {
  testWidgets('tapping Invite sends the invitation and shows a confirmation', (
    tester,
  ) async {
    final invitationRepository = await _pumpSearchWithResult(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    await tester.pump();
    await tester.pump();

    expect(invitationRepository.lastInviteeId, 'bob');
    expect(find.text('Invitation sent to bob.'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets(
    'shows the backend message when already in a chat with that user',
    (tester) async {
      await _pumpSearchWithResult(
        tester,
        invitationError: const ApiException(
          statusCode: 409,
          code: 'ALREADY_IN_CHAT',
          message: 'You already have a chat with this user.',
          details: {'chatId': 'chat1'},
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Invite'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('You already have a chat with this user.'),
        findsOneWidget,
      );
      // Falls back to the Invite button again rather than getting stuck.
      expect(find.widgetWithText(TextButton, 'Invite'), findsOneWidget);
    },
  );

  testWidgets('shows the backend message for an already-pending invitation', (
    tester,
  ) async {
    await _pumpSearchWithResult(
      tester,
      invitationError: const ApiException(
        statusCode: 409,
        code: 'INVITATION_ALREADY_PENDING',
        message:
            'There is already a pending invitation between you and this user.',
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'There is already a pending invitation between you and this user.',
      ),
      findsOneWidget,
    );
  });
}
