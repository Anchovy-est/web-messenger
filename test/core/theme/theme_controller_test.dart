import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/core/theme/theme_controller.dart';
import 'package:mobile_messenger/providers/core_providers.dart';

import '../../support/fake_secure_storage_service.dart';

void main() {
  // ThemeController._systemDefault reads WidgetsBinding.instance (to check
  // the platform's brightness) even in these otherwise-plain `test()`
  // cases — this initializes that binding without needing testWidgets'
  // full widget-pumping machinery.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'defaults to light when nothing is stored and the platform is light',
    () {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(
            FakeSecureStorageService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themeControllerProvider), AppThemeOption.light);
    },
  );

  test('loads a previously stored choice', () async {
    final storage = FakeSecureStorageService(themeOption: 'floral');
    final container = ProviderContainer(
      overrides: [secureStorageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    // Providers are lazy — reading it here is what actually constructs
    // `ThemeController` (and starts its async `_load()`). Only *after*
    // that has a chance to complete does the stored value take effect.
    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeControllerProvider), AppThemeOption.floral);
  });

  test('setOption updates state and persists the choice', () async {
    final storage = FakeSecureStorageService();
    final container = ProviderContainer(
      overrides: [secureStorageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await container
        .read(themeControllerProvider.notifier)
        .setOption(AppThemeOption.dark);

    expect(container.read(themeControllerProvider), AppThemeOption.dark);
    expect(storage.themeOption, 'dark');
  });

  test(
    'an unrecognized stored value falls back to light rather than crashing',
    () async {
      final storage = FakeSecureStorageService(
        themeOption: 'not-a-real-option',
      );
      final container = ProviderContainer(
        overrides: [secureStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      container.read(themeControllerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeControllerProvider), AppThemeOption.light);
    },
  );
}
