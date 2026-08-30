import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_providers.dart';
import 'session_controller.dart';

// Two separate controllers (rather than one shared AsyncValue) so the
// screen can tell "code was just verified" apart from "a new code was
// just sent" — both are loading/error/data(null) transitions, but the UI
// reacts to each differently (verifying navigates away, resending just
// shows a snackbar).

class VerifyCodeController extends StateNotifier<AsyncValue<void>> {
  VerifyCodeController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> submit({required String email, required String code}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final user = await _ref
          .read(authRepositoryProvider)
          .verifyEmail(email: email, code: code);
      _ref.read(sessionControllerProvider.notifier).updateUser(user);
    });
  }
}

class ResendCodeController extends StateNotifier<AsyncValue<void>> {
  ResendCodeController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> resend({required String email}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _ref.read(authRepositoryProvider).resendVerification(email: email),
    );
  }
}

final verifyCodeControllerProvider =
    StateNotifierProvider.autoDispose<VerifyCodeController, AsyncValue<void>>((
      ref,
    ) {
      return VerifyCodeController(ref);
    });

final resendCodeControllerProvider =
    StateNotifierProvider.autoDispose<ResendCodeController, AsyncValue<void>>((
      ref,
    ) {
      return ResendCodeController(ref);
    });
