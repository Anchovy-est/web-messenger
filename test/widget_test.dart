import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_messenger/app.dart';
import 'package:mobile_messenger/providers/core_providers.dart';

import 'support/fake_secure_storage_service.dart';

void main() {
  testWidgets(
    'App boots with no stored session and lands on the login screen',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // No stored tokens -> SessionController resolves straight to
            // `unauthenticated` without touching the real secure-storage
            // platform channel (unmocked in widget tests) or the network.
            secureStorageServiceProvider.overrideWithValue(
              FakeSecureStorageService(),
            ),
          ],
          child: const MessengerApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Log in'), findsWidgets);
    },
  );
}
