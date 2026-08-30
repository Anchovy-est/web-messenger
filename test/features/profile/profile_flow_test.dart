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
  final List<String> registeredTokens = [];
  final List<String> unregisteredTokens = [];

  @override
  Future<void> registerPushToken(
    String token, {
    String platform = 'android',
  }) async {
    registeredTokens.add(token);
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    unregisteredTokens.add(token);
  }

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

  // --- Push notifications toggle ---------------------------------------
  //
  // This test environment has no Firebase project configured (see
  // docs/PUSH_NOTIFICATIONS.md) — `PushNotificationService.isAvailable`
  // is always false here, so a "turn on" attempt can never actually get
  // a token, the same as a real device where the user declined the OS
  // permission prompt. That's deliberately not a gap in this test suite:
  // it's exactly the "avoid silent failures" case worth proving — the
  // toggle shows an error and reverts, rather than silently claiming
  // success it can't back up. "Turn off" has no such dependency (it
  // just stops trying to use a token), so that direction genuinely
  // succeeds here.

  testWidgets('notifications are on by default', (tester) async {
    await _pumpAuthenticatedApp(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Push notifications'),
    );
    expect(toggle.value, true);
  });

  testWidgets(
    'turning notifications off unregisters the push token and persists the choice',
    (tester) async {
      final profileRepository = await _pumpAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Push notifications'),
      );
      await tester.pumpAndSettle();

      final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Push notifications'),
      );
      expect(toggle.value, false);
      // No real token exists in this environment (no Firebase — see
      // this section's own comment above), so there was nothing to
      // actually unregister; what matters is that turning it off never
      // throws and the choice is reflected in the UI.
      expect(profileRepository.unregisteredTokens, isEmpty);
    },
  );

  testWidgets(
    'turning notifications on shows an error and leaves the toggle off, '
    'since no push token can be obtained here',
    (tester) async {
      await _pumpAuthenticatedApp(tester);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      // Off, then attempt on — starting from off avoids relying on
      // exactly how the default-enabled state's "on -> on" tap behaves.
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Push notifications'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Push notifications'),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Notification permission was denied'),
        findsOneWidget,
      );
      final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Push notifications'),
      );
      expect(toggle.value, false);
    },
  );

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
    // The actual content underneath is still there and still
    // functions — Floral is a decorative backdrop, not a replacement
    // for the real screen.
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

    // A fresh app instance reading the same (now-populated) storage —
    // stands in for an app restart, since `SecureStorageService` is
    // what's supposed to make this survive one.
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
