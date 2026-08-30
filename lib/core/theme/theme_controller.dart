import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/core_providers.dart';
import '../../services/secure_storage_service.dart';

/// The three themes a user can explicitly pick between — see
/// `AppTheme`/`ProfileScreen`'s theme picker. Unlike a plain light/dark
/// split, none of these three follow the OS setting automatically once
/// chosen; [ThemeController]'s *default*, before any explicit choice has
/// ever been made, is the one place OS brightness still matters (see its
/// doc comment).
enum AppThemeOption {
  light,
  dark,
  floral;

  static AppThemeOption fromName(String name) =>
      AppThemeOption.values.firstWhere(
        (option) => option.name == name,
        orElse: () => AppThemeOption.light,
      );
}

/// Owns which of [AppThemeOption]'s three themes is currently active,
/// persisted via [SecureStorageService] so the choice survives an app
/// restart (same "durable local preference" pattern as
/// `NotificationSettingsController`'s on/off flag).
///
/// Before the user has ever touched the theme picker, there's no stored
/// choice yet — defaulting to `AppThemeOption.light` unconditionally
/// would visibly change the app's look for anyone who was previously
/// relying on the OS's dark-mode setting (this app followed
/// `ThemeMode.system` before Floral existed). Reading the platform's
/// current brightness once, as the fallback for "nothing stored yet",
/// preserves that behavior instead of silently changing it — this
/// feature is additive, not a redesign of what already worked.
class ThemeController extends StateNotifier<AppThemeOption> {
  ThemeController(this._storage) : super(_systemDefault()) {
    _load();
  }

  final SecureStorageService _storage;

  static AppThemeOption _systemDefault() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark
        ? AppThemeOption.dark
        : AppThemeOption.light;
  }

  Future<void> _load() async {
    final stored = await _storage.readThemeOption();
    if (stored == null || !mounted) return;
    state = AppThemeOption.fromName(stored);
  }

  Future<void> setOption(AppThemeOption option) async {
    state = option;
    await _storage.writeThemeOption(option.name);
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeOption>((ref) {
      return ThemeController(ref.watch(secureStorageServiceProvider));
    });
