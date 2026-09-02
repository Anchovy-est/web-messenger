import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/profile/data/profile_providers.dart';
import 'package:mobile_messenger/features/profile/data/profile_repository.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';
import 'package:mobile_messenger/widgets/floral_background.dart';

import '../../support/compact_viewport.dart';
import '../../support/fake_chat_repository.dart';
import '../../support/fake_secure_storage_service.dart';
import '../../support/fake_socket_service.dart';

const _initialUser = User(
  id: 'u1',
  username: 'annab',
  email: 'anna@example.com',
  displayName: 'annab',
  emailVerified: false,
  avatarUrl: null,
  bio: null,
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this.currentUser) : super(ApiClient());

  User currentUser;

  @override
  Future<User> fetchCurrentUser() async => currentUser;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    return LoginResult(
      user: currentUser,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository() : super(ApiClient());

  User? lastUpdate;
  Object? errorToThrow;

  @override
  Future<User> updateProfile({
    required String username,
    required String bio,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    final updated = User(
      id: _initialUser.id,
      username: username,
      email: _initialUser.email,
      displayName: _initialUser.displayName,
      emailVerified: _initialUser.emailVerified,
      bio: bio,
    );
    lastUpdate = updated;
    return updated;
  }
}

Future<_FakeProfileRepository> _pumpAuthenticatedApp(
  WidgetTester tester,
) async {
  useCompactViewport(tester);
  final profileRepository = _FakeProfileRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(
          _FakeAuthRepository(_initialUser),
        ),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
      child: const MessengerApp(),
    ),
  );
  await tester.pumpAndSettle();
  return profileRepository;
}

void main() {
  testWidgets(
    'a fresh profile shows the default avatar icon and empty About Me',
    (tester) async {
      await _pumpAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      expect(find.text('annab'), findsOneWidget);
      expect(find.text('No bio yet.'), findsOneWidget);
      expect(
        find.byIcon(Icons.person),
        findsOneWidget,
      ); // default avatar placeholder
    },
  );

  testWidgets(
    'editing the profile updates username and bio, and it persists in the session',
    (tester) async {
      final profileRepository = await _pumpAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'newname',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'About Me'),
        'Hello there',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(profileRepository.lastUpdate?.username, 'newname');
      expect(profileRepository.lastUpdate?.bio, 'Hello there');
      expect(find.text('Profile updated.'), findsOneWidget);
      // Back on the profile screen, reflecting the update immediately.
      expect(find.text('newname'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
    },
  );

  testWidgets('rejects an empty username on the edit screen', (tester) async {
    await _pumpAuthenticatedApp(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Username is required.'), findsOneWidget);
  });

  // --- Floral theme -----------------------------------------------------

  testWidgets('switching to Floral shows the decorative flower background, and '
      'switching back to Light removes it', (tester) async {
    await _pumpAuthenticatedApp(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.byType(FloralBackground), findsNothing);

    await tester.tap(find.text('Floral'));
    await tester.pumpAndSettle();

    expect(find.byType(FloralBackground), findsOneWidget);
    // The content underneath still functions — Floral is a decorative
    // backdrop, not a replacement for the real screen.
    expect(find.text('annab'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(find.byType(FloralBackground), findsNothing);
  });

  testWidgets('the theme choice persists across a restart-equivalent reload', (
    tester,
  ) async {
    useCompactViewport(tester);
    final storage = FakeSecureStorageService(accessToken: 'token');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(_initialUser),
          ),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          socketServiceProvider.overrideWithValue(FakeSocketService()),
        ],
        child: const MessengerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floral'));
    await tester.pumpAndSettle();

    expect(storage.themeOption, 'floral');

    // A fresh app instance reading the same storage — stands in for
    // an app restart, since `SecureStorageService` is what makes this
    // survive one.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(_initialUser),
          ),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          socketServiceProvider.overrideWithValue(FakeSocketService()),
        ],
        child: const MessengerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloralBackground), findsOneWidget);
  });
}
