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
  _FakeAuthRepository({this.loginError, this.currentUser}) : super(ApiClient());

  final ApiException? loginError;
  User? currentUser;

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
      // A plain ProviderContainer (rather than the `_pumpApp` helper's
      // implicit one) so the test can reach in and drive
      // `forceLogoutLocally` directly — exactly the call
      // `ApiClient.onSessionExpired` makes when a background request's
      // silent token refresh fails, which isn't reachable by tapping
      // anything in the UI (there's no real Dio traffic in this test's
      // fakes to trigger it organically).
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
}
