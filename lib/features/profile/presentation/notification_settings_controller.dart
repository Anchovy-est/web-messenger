import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_providers.dart';
import '../data/profile_providers.dart';

/// Thrown when the user tries to turn notifications on but the OS
/// permission prompt was declined.
class NotificationPermissionDeniedException implements Exception {
  const NotificationPermissionDeniedException();
}

/// Backs the profile screen's "Push notifications" toggle. Not
/// optimistic — a brief disabled state while it resolves beats showing
/// "on" when permission was actually declined.
class NotificationSettingsController extends StateNotifier<AsyncValue<bool>> {
  NotificationSettingsController(this._ref)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final enabled = await _ref
        .read(secureStorageServiceProvider)
        .readNotificationsEnabled();
    if (!mounted) return;
    state = AsyncValue.data(enabled);
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = state;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final storage = _ref.read(secureStorageServiceProvider);
      final pushService = _ref.read(pushNotificationServiceProvider);
      final profileRepository = _ref.read(profileRepositoryProvider);

      if (enabled) {
        final token = await pushService.requestPermissionAndGetToken();
        if (token == null) {
          throw const NotificationPermissionDeniedException();
        }
        await profileRepository.registerPushToken(token);
      } else {
        final token = await pushService.getCurrentToken();
        if (token != null) {
          await profileRepository.unregisterPushToken(token);
        }
      }
      await storage.writeNotificationsEnabled(enabled);
      return enabled;
    });
    if (!mounted) return;
    if (result.hasError) {
      // Two assignments: let listeners react to the error first, then
      // settle back to what the toggle showed before.
      state = result;
      if (!mounted) return;
      state = previous;
    } else {
      state = result;
    }
  }
}

final notificationSettingsControllerProvider =
    StateNotifierProvider.autoDispose<
      NotificationSettingsController,
      AsyncValue<bool>
    >((ref) => NotificationSettingsController(ref));
