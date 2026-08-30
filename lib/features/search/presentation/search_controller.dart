import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/user.dart';
import '../data/search_providers.dart';
import '../data/search_repository.dart';

/// `data([])` doubles as both "nothing typed yet" and "no matches found" —
/// the screen tells those apart by looking at whether a query is
/// currently entered (see SearchScreen), not by inventing a third state
/// here.
class SearchController extends StateNotifier<AsyncValue<List<User>>> {
  SearchController(this._repository) : super(const AsyncValue.data([]));

  final SearchRepository _repository;
  Timer? _debounce;

  // Guards against an older, slower request's result overwriting a
  // newer one that already resolved (e.g. "al" resolves after "ali" if
  // the network reorders them) — only the response matching the latest
  // call is ever applied.
  int _requestId = 0;

  /// Called on every keystroke. Debounces network calls, and treats an
  /// empty/whitespace-only query as "no search" rather than sending a
  /// request the backend would just reject — an empty search failing
  /// server-side should never surface as an error client-side.
  void onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(trimmed),
    );
  }

  Future<void> _search(String query) async {
    final thisRequestId = ++_requestId;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _repository.searchUsers(query));
    if (thisRequestId == _requestId) {
      state = result;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchControllerProvider =
    StateNotifierProvider.autoDispose<SearchController, AsyncValue<List<User>>>(
      (ref) {
        return SearchController(ref.watch(searchRepositoryProvider));
      },
    );
