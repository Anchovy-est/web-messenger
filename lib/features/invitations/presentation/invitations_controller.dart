import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/invitation.dart';
import '../data/invitation_providers.dart';
import '../data/invitation_repository.dart';

/// Backs the "Received" tab: fetches on creation, and updates the
/// affected invitation in place after accept/decline instead of
/// refetching the whole list.
class ReceivedInvitationsController
    extends StateNotifier<AsyncValue<List<Invitation>>> {
  ReceivedInvitationsController(this._repository)
    : super(const AsyncValue.loading()) {
    refresh();
  }

  final InvitationRepository _repository;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.listReceived());
  }

  Future<void> respond(String invitationId, {required bool accept}) async {
    final updated = accept
        ? await _repository.accept(invitationId)
        : await _repository.decline(invitationId);
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final invitation in current)
        if (invitation.id == invitationId) updated else invitation,
    ]);
  }
}

/// Backs the "Sent" tab — read-only, so just fetch-and-display.
class SentInvitationsController
    extends StateNotifier<AsyncValue<List<Invitation>>> {
  SentInvitationsController(this._repository)
    : super(const AsyncValue.loading()) {
    refresh();
  }

  final InvitationRepository _repository;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.listSent());
  }
}

final receivedInvitationsControllerProvider =
    StateNotifierProvider.autoDispose<
      ReceivedInvitationsController,
      AsyncValue<List<Invitation>>
    >((ref) {
      return ReceivedInvitationsController(
        ref.watch(invitationRepositoryProvider),
      );
    });

final sentInvitationsControllerProvider =
    StateNotifierProvider.autoDispose<
      SentInvitationsController,
      AsyncValue<List<Invitation>>
    >((ref) {
      return SentInvitationsController(ref.watch(invitationRepositoryProvider));
    });
