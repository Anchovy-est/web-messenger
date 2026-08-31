import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/user.dart';
import '../data/search_providers.dart';
import '../data/search_repository.dart';

/// `data([])` doubles as both "nothing typed yet" and "no matches" —
/// the screen tells those apart by whether a query is entered.
class SearchController extends StateNotifier<AsyncValue<List<User>>> {
  SearchController(this._repository) : super(const AsyncValue.data([]));

  final SearchRepository _repository;
  Timer? _debounce;

  // Guards against an older, slower request overwriting a newer one.
  int _requestId = 0;

  /// Debounces network calls; an empty query means "no search".
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
