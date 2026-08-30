import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/invitations/data/invitation_providers.dart';
import 'package:mobile_messenger/features/invitations/data/invitation_repository.dart';
import 'package:mobile_messenger/features/invitations/presentation/invitations_screen.dart';
import 'package:mobile_messenger/models/invitation.dart';
import 'package:mobile_messenger/services/api_client.dart';

const _bob = InvitationParticipant(
  id: 'bob',
  username: 'bob',
  displayName: 'Bob',
);
const _carol = InvitationParticipant(
  id: 'carol',
  username: 'carol',
  displayName: 'Carol',
);
final _now = DateTime(2026, 1, 1);

Invitation _invitation({
  required String id,
  required InvitationStatus status,
  InvitationParticipant inviter = _bob,
  InvitationParticipant invitee = _carol,
}) {
  return Invitation(
    id: id,
    chatId: 'chat-$id',
    status: status,
    createdAt: _now,
    inviter: inviter,
    invitee: invitee,
  );
}

class _FakeInvitationRepository extends InvitationRepository {
  _FakeInvitationRepository({
    List<Invitation> received = const [],
    this.sentList = const [],
    this.errorOnReceived,
  }) : receivedList = received,
       super(ApiClient());

  List<Invitation> receivedList;
  final List<Invitation> sentList;
  final ApiException? errorOnReceived;
  final List<String> acceptedIds = [];
  final List<String> declinedIds = [];

  @override
  Future<List<Invitation>> listReceived({InvitationStatus? status}) async {
    if (errorOnReceived != null) throw errorOnReceived!;
    return receivedList;
  }

  @override
  Future<List<Invitation>> listSent({InvitationStatus? status}) async =>
      sentList;

  @override
  Future<Invitation> accept(String invitationId) async {
    acceptedIds.add(invitationId);
    return _respond(invitationId, InvitationStatus.accepted);
  }

  @override
  Future<Invitation> decline(String invitationId) async {
    declinedIds.add(invitationId);
    return _respond(invitationId, InvitationStatus.declined);
  }

  Invitation _respond(String invitationId, InvitationStatus newStatus) {
    final original = receivedList.firstWhere((i) => i.id == invitationId);
    final updated = _invitation(
      id: original.id,
      status: newStatus,
      inviter: original.inviter,
      invitee: original.invitee,
    );
    receivedList = [
      for (final i in receivedList)
        if (i.id == invitationId) updated else i,
    ];
    return updated;
  }
}

Future<void> _pumpInvitationsScreen(
  WidgetTester tester, {
  required _FakeInvitationRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [invitationRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: InvitationsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'shows received invitations with accept/decline for pending ones',
    (tester) async {
      final repository = _FakeInvitationRepository(
        received: [_invitation(id: 'i1', status: InvitationStatus.pending)],
      );
      await _pumpInvitationsScreen(tester, repository: repository);

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('Wants to chat with you'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    },
  );

  testWidgets(
    'accepting an invitation updates it in place and hides the buttons',
    (tester) async {
      final repository = _FakeInvitationRepository(
        received: [_invitation(id: 'i1', status: InvitationStatus.pending)],
      );
      await _pumpInvitationsScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump();
      await tester.pump();

      expect(repository.acceptedIds, ['i1']);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    },
  );

  testWidgets('declining an invitation updates it in place', (tester) async {
    final repository = _FakeInvitationRepository(
      received: [_invitation(id: 'i1', status: InvitationStatus.pending)],
    );
    await _pumpInvitationsScreen(tester, repository: repository);

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    await tester.pump();

    expect(repository.declinedIds, ['i1']);
    expect(find.text('Declined'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no received invitations', (
    tester,
  ) async {
    final repository = _FakeInvitationRepository(received: const []);
    await _pumpInvitationsScreen(tester, repository: repository);

    expect(find.text('No invitations yet.'), findsOneWidget);
  });

  testWidgets('shows an error with retry when loading fails', (tester) async {
    final repository = _FakeInvitationRepository(
      errorOnReceived: const ApiException(
        statusCode: 500,
        code: 'INTERNAL_ERROR',
        message: 'Something went wrong.',
      ),
    );
    await _pumpInvitationsScreen(tester, repository: repository);

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets(
    'the Sent tab shows sent invitations with status, no accept/decline',
    (tester) async {
      final repository = _FakeInvitationRepository(
        sentList: [
          _invitation(id: 's1', status: InvitationStatus.pending),
          _invitation(id: 's2', status: InvitationStatus.declined),
        ],
      );
      await _pumpInvitationsScreen(tester, repository: repository);

      await tester.tap(find.text('Sent'));
      await tester.pumpAndSettle();

      expect(find.text('carol'), findsNWidgets(2));
      expect(find.text('Waiting for a response'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    },
  );
}
