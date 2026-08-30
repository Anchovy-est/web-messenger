import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_providers.dart';

class ForgotPasswordController extends StateNotifier<AsyncValue<void>> {
  ForgotPasswordController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> submit({required String email}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _ref.read(authRepositoryProvider).forgotPassword(email: email),
    );
  }
}

class ResetPasswordController extends StateNotifier<AsyncValue<void>> {
  ResetPasswordController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> submit({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _ref
          .read(authRepositoryProvider)
          .resetPassword(email: email, code: code, newPassword: newPassword),
    );
  }
}

final forgotPasswordControllerProvider =
    StateNotifierProvider.autoDispose<
      ForgotPasswordController,
      AsyncValue<void>
    >((ref) {
      return ForgotPasswordController(ref);
    });

final resetPasswordControllerProvider =
    StateNotifierProvider.autoDispose<
      ResetPasswordController,
      AsyncValue<void>
    >((ref) {
      return ResetPasswordController(ref);
    });
