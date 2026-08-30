import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/user.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/profile_providers.dart';

class EditProfileController extends StateNotifier<AsyncValue<void>> {
  EditProfileController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> submit({required String username, required String bio}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final User updated = await _ref
          .read(profileRepositoryProvider)
          .updateProfile(username: username, bio: bio);
      // Reflect the change everywhere the session's user is shown
      // (profile screen, home banner, etc.) without a re-login round trip.
      _ref.read(sessionControllerProvider.notifier).updateUser(updated);
    });
  }
}

final editProfileControllerProvider =
    StateNotifierProvider.autoDispose<EditProfileController, AsyncValue<void>>((
      ref,
    ) {
      return EditProfileController(ref);
    });
