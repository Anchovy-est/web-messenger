import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/search/data/search_providers.dart';
import 'package:mobile_messenger/features/search/data/search_repository.dart';
import 'package:mobile_messenger/features/search/presentation/search_screen.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/services/api_client.dart';

const _alice = User(
  id: 'u1',
  username: 'alice_search',
  email: 'alice@example.com',
  displayName: 'alice_search',
  emailVerified: false,
);

class _FakeSearchRepository extends SearchRepository {
  _FakeSearchRepository({this.results = const [], this.errorToThrow})
    : super(ApiClient());

  final List<User> results;
  final ApiException? errorToThrow;
  String? lastQuery;

  @override
  Future<List<User>> searchUsers(String query) async {
    lastQuery = query;
    if (errorToThrow != null) throw errorToThrow!;
    return results;
  }
}

Future<void> _pumpSearchScreen(
  WidgetTester tester, {
  required _FakeSearchRepository repository,
}) async {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [searchRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a neutral prompt when nothing has been typed', (
    tester,
  ) async {
    await _pumpSearchScreen(tester, repository: _FakeSearchRepository());

    expect(
      find.text('Search for someone by username or email'),
      findsOneWidget,
    );
  });

  testWidgets('finds an existing user and shows it in the results', (
    tester,
  ) async {
    final repository = _FakeSearchRepository(results: const [_alice]);
    await _pumpSearchScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // let the debounce fire
    await tester.pumpAndSettle();

    expect(repository.lastQuery, 'alice');
    expect(find.text('alice_search'), findsOneWidget);
  });

  testWidgets('shows "No users found." for a nonexistent user', (tester) async {
    final repository = _FakeSearchRepository(results: const []);
    await _pumpSearchScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextField), 'nobody_at_all');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('No users found.'), findsOneWidget);
  });

  testWidgets(
    'clearing the query back to empty returns to the neutral prompt, not an error',
    (tester) async {
      final repository = _FakeSearchRepository(results: const [_alice]);
      await _pumpSearchScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('alice_search'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(
        find.text('Search for someone by username or email'),
        findsOneWidget,
      );
      // Clearing to empty must not have triggered a network call for ''.
      expect(repository.lastQuery, 'alice');
    },
  );

  testWidgets(
    'a whitespace-only query is treated the same as empty (no request sent)',
    (tester) async {
      final repository = _FakeSearchRepository(results: const [_alice]);
      await _pumpSearchScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        find.text('Search for someone by username or email'),
        findsOneWidget,
      );
      expect(repository.lastQuery, isNull);
    },
  );

  testWidgets('shows the backend error message on failure', (tester) async {
    final repository = _FakeSearchRepository(
      errorToThrow: const ApiException(
        statusCode: 400,
        code: 'VALIDATION_ERROR',
        message: 'Search query is too long.',
      ),
    );
    await _pumpSearchScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextField), 'a very long query');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Search query is too long.'), findsOneWidget);
  });

  testWidgets(
    'the search field caps input at 100 characters (matches backend limit)',
    (tester) async {
      await _pumpSearchScreen(tester, repository: _FakeSearchRepository());

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, 100);
    },
  );
}
