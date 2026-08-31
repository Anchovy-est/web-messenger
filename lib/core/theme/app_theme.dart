import 'package:flutter/material.dart';

import 'floral_palette.dart';

/// Single source of truth for the app's visual theme.
class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF3D5AFE);

  // Shared outline style for every text field (search-in-app-bar fields
  // opt out with their own `InputBorder.none`).
  static const _inputDecorationTheme = InputDecorationTheme(
    border: OutlineInputBorder(),
  );

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      inputDecorationTheme: _inputDecorationTheme,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      inputDecorationTheme: _inputDecorationTheme,
    );
  }

  /// A soft botanical/glassmorphism theme: pastel surfaces, translucent
  /// cards/dialogs/bubbles, and decorative flowers behind everything
  /// (see `FloralBackground`). Hand-authored, not seeded, so every
  /// color role stays legible against its surface.
  static ThemeData floral() {
    const ink = FloralPalette.ink;
    const inkMuted = FloralPalette.inkMuted;

    final colorScheme = const ColorScheme.light(
      primary: FloralPalette.softCoral,
      onPrimary: ink,
      primaryContainer: FloralPalette.pastelPink,
      onPrimaryContainer: ink,
      secondary: FloralPalette.lavender,
      onSecondary: ink,
      secondaryContainer: FloralPalette.lilac,
      onSecondaryContainer: ink,
      tertiary: FloralPalette.mint,
      onTertiary: ink,
      tertiaryContainer: FloralPalette.sage,
      onTertiaryContainer: ink,
      // A softened, dusty rose-red instead of a saturated one.
      error: Color(0xFFE3A9A0),
      onError: Color(0xFF4A2620),
      errorContainer: Color(0xFFF6DCD8),
      onErrorContainer: Color(0xFF6B3A33),
      surface: FloralPalette.cream,
      onSurface: ink,
      // Translucent on purpose, for the glassy look over the flowers.
      surfaceContainerHighest: Color(0xE6E7ECF7),
      onSurfaceVariant: inkMuted,
      outline: Color(0xFFCBB3BB),
      outlineVariant: Color(0xFFE3D2D8),
      // SnackBar styling: an ink-colored pill with pale text.
      inverseSurface: ink,
      onInverseSurface: FloralPalette.cream,
      inversePrimary: FloralPalette.pastelPink,
      surfaceTint: FloralPalette.softCoral,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Transparent — `FloralBackground` paints the cream base + flowers.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: FloralPalette.cream.withValues(alpha: 0.85),
        foregroundColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.55),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: FloralPalette.cream.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: FloralPalette.cream.withValues(alpha: 0.95),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: FloralPalette.cream),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
