import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/profile_providers.dart';

class AvatarUploadController extends StateNotifier<AsyncValue<void>> {
  AvatarUploadController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> upload(String filePath) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final user = await _ref
          .read(profileRepositoryProvider)
          .uploadAvatar(filePath);
      _ref.read(sessionControllerProvider.notifier).updateUser(user);
    });
  }
}

final avatarUploadControllerProvider =
    StateNotifierProvider.autoDispose<AvatarUploadController, AsyncValue<void>>(
      (ref) {
        return AvatarUploadController(ref);
      },
    );
