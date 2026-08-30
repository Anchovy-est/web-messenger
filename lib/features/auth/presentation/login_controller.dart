import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_controller.dart';

/// Tracks the loading/error state of a single login form submission.
/// The actual session state lives in [SessionController] — this only
/// exists so the login screen has something to show a spinner/error for
/// while that call is in flight.
class LoginController extends StateNotifier<AsyncValue<void>> {
  LoginController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  Future<void> submit({required String email, required String password}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _ref
          .read(sessionControllerProvider.notifier)
          .login(email: email, password: password),
    );
  }
}

final loginControllerProvider =
    StateNotifierProvider.autoDispose<LoginController, AsyncValue<void>>((ref) {
      return LoginController(ref);
    });
