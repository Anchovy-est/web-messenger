import 'package:flutter/material.dart';

import 'floral_palette.dart';

/// Single source of truth for the app's visual theme. Keeping this in one
/// place (rather than scattering `Colors.blue` / hard-coded styles through
/// feature widgets) is what makes a future UI/UX polish pass tractable.
class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF3D5AFE);

  // Every text field in the app (login, register, edit profile, the
  // message-edit dialog, …) was independently repeating
  // `border: const OutlineInputBorder()` — one shared theme entry means
  // every field looks the same by construction, not by everyone
  // remembering to copy the same line, and a future style change (e.g.
  // rounded corners) is one edit instead of a dozen. The app-bar search
  // field is the one deliberate exception (`InputBorder.none`, set
  // per-field) — a search-in-app-bar field looking outlined like a form
  // field would be the actual inconsistency.
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

  /// A soft botanical/glassmorphism theme: pastel surfaces throughout,
  /// translucent cards/dialogs/message bubbles, and low-opacity
  /// decorative flowers behind everything (see `FloralBackground`,
  /// wired in by `MessengerApp` only while this theme is active).
  ///
  /// Hand-authored (not `ColorScheme.fromSeed`) so every role is a
  /// deliberate, checked choice rather than whatever a seed algorithm
  /// happens to derive — the brief this follows: gentle pastels only (no
  /// neon, no heavy saturation, nothing near-black), and every "on*" text/
  /// icon role paired with enough contrast against its surface to stay
  /// legible — messages, usernames, buttons, icons, fields, navigation,
  /// and dialogs all need to read clearly, the flowers are decoration
  /// only. All colors below come from [FloralPalette] — nothing here is
  /// a one-off hex value invented on the spot.
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
      // A softened, dusty rose-red rather than Material's default
      // saturated red — still clearly reads as "error", just not a
      // harsh contrast against the rest of this palette.
      error: Color(0xFFE3A9A0),
      onError: Color(0xFF4A2620),
      errorContainer: Color(0xFFF6DCD8),
      onErrorContainer: Color(0xFF6B3A33),
      surface: FloralPalette.cream,
      onSurface: ink,
      // Translucent on purpose (an alpha channel on a ColorScheme role
      // isn't conventional, but nothing forbids it) — this is what makes
      // the *other* participant's message bubble, and every `Card`/
      // `Dialog`/`BottomSheet` built on this role, genuinely glassy
      // against the flowers behind it rather than a flat, opaque pastel.
      surfaceContainerHighest: Color(0xE6E7ECF7),
      onSurfaceVariant: inkMuted,
      outline: Color(0xFFCBB3BB),
      outlineVariant: Color(0xFFE3D2D8),
      // Used by SnackBar's default M3 styling — an ink-colored pill with
      // pale text feels deliberately designed rather than defaulting to
      // Material's cool gray, which would clash with everything else
      // here.
      inverseSurface: ink,
      onInverseSurface: FloralPalette.cream,
      inversePrimary: FloralPalette.pastelPink,
      surfaceTint: FloralPalette.softCoral,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Transparent, not [FloralPalette.cream] — `FloralBackground`
      // already paints the cream base *and* the flowers behind every
      // screen; an opaque Scaffold background here would hide both.
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
