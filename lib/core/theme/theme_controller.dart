import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/core_providers.dart';
import '../../services/secure_storage_service.dart';

/// The three themes a user can pick between. None follow the OS setting
/// once explicitly chosen.
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

/// Which theme is active, persisted so the choice survives a restart.
/// Defaults to the OS's current brightness until the user picks one
/// explicitly, so nobody's dark-mode preference silently changes.
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
