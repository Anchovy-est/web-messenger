import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_providers.dart';
import '../data/profile_providers.dart';

/// Thrown by [NotificationSettingsController.setEnabled] when the user
/// tries to turn notifications *on* but the OS permission prompt was
/// actually declined — distinct from a plain [ApiException] so the
/// profile screen can show a message that's actually about what
/// happened, not a generic network-error string.
class NotificationPermissionDeniedException implements Exception {
  const NotificationPermissionDeniedException();
}

/// Backs the profile screen's "Push notifications" toggle. Reads/writes
/// [SecureStorageService.readNotificationsEnabled] as the durable
/// record of the user's own choice (see that method's doc comment for
/// why "never set" defaults to enabled), and drives the actual
/// permission request / token register-or-unregister through
/// [PushNotificationService] + [ProfileRepository].
///
/// Deliberately *not* optimistic: this is a rare, deliberate action, not
/// something that benefits from an instant-feedback illusion, and
/// getting it visibly wrong (showing "on" when the permission prompt was
/// actually declined) would be worse than a brief disabled state while
/// the toggle resolves.
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
      // Two separate assignments, deliberately: the first lets anything
      // listening for the failure (the profile screen's SnackBar) react
      // to it, and the second settles the toggle back to exactly what
      // it showed before — see the class doc comment on why this isn't
      // optimistic. Collapsing this into one assignment would mean the
      // error state never actually exists as far as any listener can
      // observe, silently losing it.
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
