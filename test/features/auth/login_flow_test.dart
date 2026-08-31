import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/auth/presentation/session_controller.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';

import '../../support/compact_viewport.dart';
import '../../support/fake_chat_repository.dart';
import '../../support/fake_secure_storage_service.dart';
import '../../support/fake_socket_service.dart';

const _fakeUser = User(
  id: 'u1',
  username: 'annab',
  email: 'anna@example.com',
  displayName: 'Anna',
  emailVerified: false,
);

/// Fakes the whole backend surface the session flow touches: login,
/// fetchCurrentUser (session restore), and logout.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.loginError, this.currentUser, this.restoreError})
    : super(ApiClient());

  final ApiException? loginError;
  User? currentUser;

  /// Overrides what [fetchCurrentUser] throws — lets a test simulate
  /// the backend being unreachable (a network/timeout/5xx
  /// `ApiException`), as opposed to the default "no session" 401 below.
  ApiException? restoreError;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    if (loginError != null) throw loginError!;
    currentUser = _fakeUser;
    return const LoginResult(
      user: _fakeUser,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }

  @override
  Future<User> fetchCurrentUser() async {
    if (restoreError != null) throw restoreError!;
    if (currentUser == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'No session',
      );
    }
    return currentUser!;
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    currentUser = null;
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _FakeAuthRepository repository,
  FakeSecureStorageService? storage,
}) async {
  useCompactViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          storage ?? FakeSecureStorageService(),
        ),
        authRepositoryProvider.overrideWithValue(repository),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
      child: const MessengerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'logging in with valid credentials navigates to the home screen',
    (tester) async {
      await _pumpApp(tester, repository: _FakeAuthRepository());

      expect(find.text('Log in'), findsWidgets);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'anna@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Mobile Messenger'), findsWidgets);
      expect(find.textContaining('No chats yet.'), findsOneWidget);
    },
  );

  testWidgets('wrong credentials show an error and stay on the login screen', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      repository: _FakeAuthRepository(
        loginError: const ApiException(
          statusCode: 401,
          code: 'INVALID_CREDENTIALS',
          message: 'Incorrect email or password.',
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'anna@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrongpassword',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets); // still on the login screen
  });

  testWidgets(
    'a stored session restores straight to the home screen (skips login)',
    (tester) async {
      final repository = _FakeAuthRepository(currentUser: _fakeUser);
      await _pumpApp(
        tester,
        repository: repository,
        storage: FakeSecureStorageService(accessToken: 'stored-access-token'),
      );

      expect(find.textContaining('No chats yet.'), findsOneWidget);
      expect(find.text('Log in'), findsNothing);
    },
  );

  testWidgets('logging out returns to the login screen', (tester) async {
    final repository = _FakeAuthRepository(currentUser: _fakeUser);
    await _pumpApp(
      tester,
      repository: repository,
      storage: FakeSecureStorageService(
        accessToken: 'stored-access-token',
        refreshToken: 'stored-refresh-token',
      ),
    );
    expect(find.textContaining('No chats yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
  });

  testWidgets(
    'an expired session shows an explanatory message on the login screen',
    (tester) async {
      final repository = _FakeAuthRepository(currentUser: _fakeUser);
      // A plain ProviderContainer so the test can reach in and drive
      // `forceLogoutLocally` directly — the call
      // `ApiClient.onSessionExpired` makes on a failed silent refresh,
      // not reachable by tapping anything in this test's fakes.
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(
            FakeSecureStorageService(accessToken: 'stored-access-token'),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          socketServiceProvider.overrideWithValue(FakeSocketService()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MessengerApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No chats yet.'), findsOneWidget);

      await container
          .read(sessionControllerProvider.notifier)
          .forceLogoutLocally();
      await tester.pumpAndSettle();

      expect(find.text('Log in'), findsWidgets);
      expect(
        find.text('Your session has expired. Please log in again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a normal logout does not show the session-expired message', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(currentUser: _fakeUser);
    await _pumpApp(
      tester,
      repository: repository,
      storage: FakeSecureStorageService(
        accessToken: 'stored-access-token',
        refreshToken: 'stored-refresh-token',
      ),
    );

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsWidgets);
    expect(
      find.text('Your session has expired. Please log in again.'),
      findsNothing,
    );
  });

  // --- Session restore vs. backend/network failure ---------------------

  testWidgets(
    'a stored session that cannot be reached at startup shows a retry '
    'screen, not a forced logout',
    (tester) async {
      final repository = _FakeAuthRepository(
        currentUser: _fakeUser,
        restoreError: const ApiException(
          statusCode: null,
          code: 'NETWORK_ERROR',
          message: 'No internet connection detected.',
        ),
      );
      final storage = FakeSecureStorageService(
        accessToken: 'stored-access-token',
        refreshToken: 'stored-refresh-token',
      );

      await _pumpApp(tester, repository: repository, storage: storage);

      // The generic headline, plus this specific failure's own message.
      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('No internet connection detected.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      // Not bounced to the login screen — a connectivity failure must
      // never look identical to "you are logged out".
      expect(find.text('Log in'), findsNothing);
      // The tokens are still there — a failure to reach the server
      // shouldn't discard a session that might still be valid.
      expect(await storage.readAccessToken(), 'stored-access-token');
    },
  );

  testWidgets(
    'retrying a failed restore succeeds once the backend is reachable '
    'again',
    (tester) async {
      final repository = _FakeAuthRepository(
        currentUser: _fakeUser,
        restoreError: const ApiException(
          statusCode: 503,
          code: 'SERVICE_UNAVAILABLE',
          message: 'The service is temporarily unavailable.',
        ),
      );
      await _pumpApp(
        tester,
        repository: repository,
        storage: FakeSecureStorageService(
          accessToken: 'stored-access-token',
          refreshToken: 'stored-refresh-token',
        ),
      );
      expect(
        find.text('The service is temporarily unavailable.'),
        findsOneWidget,
      );

      // The backend is reachable again by the time the user retries.
      repository.restoreError = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No chats yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'a stored session the backend actually rejects (not just unreachable) '
    'does land on the login screen',
    (tester) async {
      final repository = _FakeAuthRepository(
        restoreError: const ApiException(
          statusCode: 401,
          code: 'UNAUTHENTICATED',
          message: 'Invalid or expired token.',
        ),
      );
      await _pumpApp(
        tester,
        repository: repository,
        storage: FakeSecureStorageService(
          accessToken: 'stale-access-token',
          refreshToken: 'stale-refresh-token',
        ),
      );

      expect(find.text('Log in'), findsWidgets);
      expect(find.text('Could not reach the server.'), findsNothing);
    },
  );
}
