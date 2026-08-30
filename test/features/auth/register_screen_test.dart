import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/presentation/register_screen.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/services/api_client.dart';

/// Overrides [AuthRepository.register] instead of hitting the network, so
/// this test exercises the widget's own validation/state-wiring logic in
/// isolation from the backend.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.userToReturn, this.errorToThrow})
    : super(ApiClient());

  final User? userToReturn;
  final ApiException? errorToThrow;

  @override
  Future<User> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return userToReturn!;
  }
}

const _fakeUser = User(
  id: 'u1',
  username: 'annab',
  email: 'anna@example.com',
  displayName: 'annab',
  emailVerified: false,
);

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Username'),
    'annab',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email'),
    'anna@example.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'Password123!',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Confirm password'),
    'Password123!',
  );
}

void main() {
  testWidgets('shows client-side validation errors on empty submit', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(userToReturn: _fakeUser),
          ),
        ],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();

    expect(find.text('Username is required.'), findsOneWidget);
    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });

  testWidgets('rejects mismatched passwords', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(userToReturn: _fakeUser),
          ),
        ],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'annab',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'anna@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Password123!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'Different123!',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets(
    'rejects a password missing a required character class, and shows '
    'which rules are/aren\'t met live as the user types',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              _FakeAuthRepository(userToReturn: _fakeUser),
            ),
          ],
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );

      // All lowercase and digits — 8+ characters, but no uppercase and no
      // special character, so two of the five rules stay unmet.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.pump();

      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(find.text('One lowercase letter'), findsOneWidget);
      expect(find.text('One number'), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(
        find.text('Password must contain at least one uppercase letter.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('submits and shows success snackbar on valid input', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(userToReturn: _fakeUser),
          ),
        ],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );

    await _fillValidForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump(); // triggers loading state
    await tester.pump(); // lets the fake future resolve

    expect(find.text('Account created! You can now log in.'), findsOneWidget);
  });

  testWidgets(
    'shows backend conflict error (e.g. EMAIL_TAKEN) as a form-level message',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              _FakeAuthRepository(
                errorToThrow: const ApiException(
                  statusCode: 409,
                  code: 'EMAIL_TAKEN',
                  message: 'Email is already registered.',
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );

      await _fillValidForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Email is already registered.'), findsOneWidget);
    },
  );
}
