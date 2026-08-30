import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/core/api_exception.dart';
import 'package:mobile_messenger/features/auth/data/auth_providers.dart';
import 'package:mobile_messenger/features/auth/data/auth_repository.dart';
import 'package:mobile_messenger/features/auth/data/login_result.dart';
import 'package:mobile_messenger/features/chats/data/chat_providers.dart';
import 'package:mobile_messenger/features/profile/data/profile_providers.dart';
import 'package:mobile_messenger/features/profile/data/profile_repository.dart';
import 'package:mobile_messenger/features/profile/presentation/avatar_upload_controller.dart';
import 'package:mobile_messenger/models/user.dart';
import 'package:mobile_messenger/providers/core_providers.dart';
import 'package:mobile_messenger/services/api_client.dart';
import 'package:mobile_messenger/widgets/user_avatar.dart';

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
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(ApiClient());

  @override
  Future<User> fetchCurrentUser() async => _initialUser;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    return LoginResult(
      user: _initialUser,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({this.errorToThrow, this.delay = Duration.zero})
    : super(ApiClient());

  final ApiException? errorToThrow;
  final Duration delay;
  String? lastUploadedPath;

  @override
  Future<User> uploadAvatar(String filePath) async {
    lastUploadedPath = filePath;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (errorToThrow != null) throw errorToThrow!;
    return const User(
      id: 'u1',
      username: 'annab',
      email: 'anna@example.com',
      displayName: 'annab',
      emailVerified: false,
      avatarUrl: '/uploads/avatars/u1-123.png',
    );
  }
}

Future<void> _pumpAuthenticatedApp(
  WidgetTester tester, {
  required _FakeProfileRepository profileRepository,
}) async {
  useCompactViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(
          FakeSecureStorageService(accessToken: 'token'),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
      child: const MessengerApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.person_outline));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a successful avatar upload updates the URL UserAvatar renders', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository();
    await _pumpAuthenticatedApp(tester, profileRepository: profileRepository);

    // Bypass the platform image picker (not mockable via Riverpod
    // overrides) and drive the same controller the picker would call.
    final element = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(element);
    await container
        .read(avatarUploadControllerProvider.notifier)
        .upload('/fake/path/photo.png');
    // A bounded pump, not pumpAndSettle: a NetworkImage that fails to
    // load (as it always will here — there's no real server behind
    // '/uploads/avatars/u1-123.png' in a widget test) can keep
    // rescheduling frames, which makes pumpAndSettle's "wait until
    // nothing is scheduled" heuristic unreliable. UserAvatar itself
    // falls back to the placeholder icon on a load error (see
    // lib/widgets/user_avatar.dart) — that fallback, not a successfully
    // decoded image, is what real widget tests can actually observe.
    await tester.pump();

    expect(profileRepository.lastUploadedPath, '/fake/path/photo.png');
    // Confirms the *data* flowed through to the widget — the real
    // network fetch behind it isn't something a widget test can
    // meaningfully assert on.
    final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
    expect(avatar.avatarUrl, '/uploads/avatars/u1-123.png');
  });

  testWidgets('shows a loading indicator while the upload is in flight', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(
      delay: const Duration(milliseconds: 200),
    );
    await _pumpAuthenticatedApp(tester, profileRepository: profileRepository);

    final element = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(element);
    // Deliberately not awaited here — awaiting it directly alongside a
    // real (non-fake-clock) `Future.delayed` inside the fake repository
    // reliably hung this test; `tester.pump(duration)` below both
    // advances past that delay and lets the test framework's own event
    // loop interleave with it, which is the supported way to drive a
    // real timer-backed async operation in a widget test.
    unawaited(
      container
          .read(avatarUploadControllerProvider.notifier)
          .upload('/fake/path/photo.png'),
    );
    await tester.pump(); // let the loading state land

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(
      const Duration(milliseconds: 250),
    ); // past the 200ms fake delay

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the backend error for an oversized/invalid-format file', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(
      errorToThrow: const ApiException(
        statusCode: 400,
        code: 'FILE_TOO_LARGE',
        message: 'File exceeds the maximum allowed size.',
      ),
    );
    await _pumpAuthenticatedApp(tester, profileRepository: profileRepository);

    final element = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(element);
    await container
        .read(avatarUploadControllerProvider.notifier)
        .upload('/fake/path/huge.png');
    await tester.pump();

    expect(find.text('File exceeds the maximum allowed size.'), findsOneWidget);
  });
}
