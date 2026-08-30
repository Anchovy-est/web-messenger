import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/user.dart';
import '../data/auth_providers.dart';
import '../data/auth_repository.dart';

/// Holds the state of an in-flight (or just-finished) registration
/// submission. `AsyncValue<User?>` starts as data(null) — "nothing
/// submitted yet" — and becomes loading/data/error once [submit] runs.
class RegisterController extends StateNotifier<AsyncValue<User?>> {
  RegisterController(this._repository) : super(const AsyncValue.data(null));

  final AuthRepository _repository;

  Future<void> submit({
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repository.register(
        username: username,
        email: email,
        password: password,
      ),
    );
  }

  void reset() => state = const AsyncValue.data(null);
}

final registerControllerProvider =
    StateNotifierProvider.autoDispose<RegisterController, AsyncValue<User?>>((
      ref,
    ) {
      return RegisterController(ref.watch(authRepositoryProvider));
    });
