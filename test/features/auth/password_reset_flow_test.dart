import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/presentation/forgot_password_screen.dart';
import 'package:mobile_messenger/features/auth/presentation/reset_password_screen.dart';
import 'package:mobile_messenger/services/api_client.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.resetError}) : super(ApiClient());

  final ApiException? resetError;
  String? lastForgotEmail;
  Map<String, String>? lastResetArgs;

  @override
  Future<void> forgotPassword({required String email}) async {
    lastForgotEmail = email;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    if (resetError != null) throw resetError!;
    lastResetArgs = {'email': email, 'code': code, 'newPassword': newPassword};
  }
}

Future<GoRouter> _pumpForgotPasswordFlow(
  WidgetTester tester, {
  required _FakeAuthRepository repository,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('Login Screen')),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/forgot-password');
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'submitting an email on forgot-password navigates to reset-password with the email prefilled',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpForgotPasswordFlow(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'anna@example.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
      await tester.pumpAndSettle();

      expect(repository.lastForgotEmail, 'anna@example.com');
      expect(find.text('Reset password'), findsWidgets);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      final emailField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Email'),
      );
      expect(emailField.controller?.text, 'anna@example.com');
    },
  );

  testWidgets(
    'reset-password rejects a non-6-digit code and mismatched passwords',
    (tester) async {
      final repository = _FakeAuthRepository();
      final router = await _pumpForgotPasswordFlow(
        tester,
        repository: repository,
      );
      router.push('/reset-password?email=anna@example.com');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Code'), '123');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'Password123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'Different123!',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
      await tester.pump();

      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
      expect(find.text('Passwords do not match.'), findsOneWidget);
    },
  );

  testWidgets('reset-password shows the backend error for a wrong code', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      resetError: const ApiException(
        statusCode: 400,
        code: 'INVALID_CODE',
        message: 'That code is invalid or has expired.',
      ),
    );
    final router = await _pumpForgotPasswordFlow(
      tester,
      repository: repository,
    );
    router.push('/reset-password?email=anna@example.com');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Code'),
      '000000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'Password123!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'Password123!',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That code is invalid or has expired.'), findsOneWidget);
  });

  testWidgets(
    'a successful reset shows a confirmation and returns to the login screen',
    (tester) async {
      final repository = _FakeAuthRepository();
      final router = await _pumpForgotPasswordFlow(
        tester,
        repository: repository,
      );
      router.push('/reset-password?email=anna@example.com');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Code'),
        '123456',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'NewPassword123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'NewPassword123!',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(repository.lastResetArgs, {
        'email': 'anna@example.com',
        'code': '123456',
        'newPassword': 'NewPassword123!',
      });
      expect(find.text('Password reset! You can now log in.'), findsOneWidget);
      expect(find.text('Login Screen'), findsOneWidget);
    },
  );
}
