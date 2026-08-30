import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/presentation/verify_email_screen.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';

import '../../support/fake_secure_storage_service.dart';

const _unverifiedUser = User(
  id: 'u1',
  username: 'annab',
  email: 'anna@example.com',
  displayName: 'Anna',
  emailVerified: false,
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.verifyError}) : super(ApiClient());

  final ApiException? verifyError;
  int resendCallCount = 0;

  @override
  Future<User> fetchCurrentUser() async => _unverifiedUser;

  @override
  Future<User> verifyEmail({
    required String email,
    required String code,
  }) async {
    if (verifyError != null) throw verifyError!;
    return const User(
      id: 'u1',
      username: 'annab',
      email: 'anna@example.com',
      displayName: 'Anna',
      emailVerified: true,
    );
  }

  @override
  Future<void> resendVerification({required String email}) async {
    resendCallCount++;
  }
}

Future<GoRouter> _pumpVerifyScreen(
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
        path: '/verify-email',
        builder: (context, state) => const VerifyEmailScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/verify-email');
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('rejects a code that is not 6 digits', (tester) async {
    await _pumpVerifyScreen(tester, repository: _FakeAuthRepository());

    await tester.enterText(find.byType(TextFormField), '123');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pump();

    expect(find.text('Enter the 6-digit code.'), findsOneWidget);
  });

  testWidgets('shows the backend error for a wrong code', (tester) async {
    await _pumpVerifyScreen(
      tester,
      repository: _FakeAuthRepository(
        verifyError: const ApiException(
          statusCode: 400,
          code: 'INVALID_CODE',
          message: 'That code is invalid or has expired.',
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That code is invalid or has expired.'), findsOneWidget);
  });

  testWidgets(
    'a correct code shows a confirmation snackbar and navigates back',
    (tester) async {
      await _pumpVerifyScreen(tester, repository: _FakeAuthRepository());

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pump();
      await tester.pump();
      await tester.pump(); // let the pop's route transition settle

      expect(find.text('Email verified!'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets('resend calls the repository and shows a snackbar', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpVerifyScreen(tester, repository: repository);

    await tester.tap(find.text("Didn't get a code? Resend"));
    await tester.pump();
    await tester.pump();

    expect(repository.resendCallCount, 1);
    expect(find.text('A new code has been sent.'), findsOneWidget);
  });
}
