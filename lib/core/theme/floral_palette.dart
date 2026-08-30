import 'package:flutter/material.dart';

/// The Floral theme's curated pastel palette — every color used anywhere
/// in the Floral theme (background, surfaces, decorative flowers) is
/// drawn from this one place, so "does this still look like the same
/// theme" is guaranteed by construction rather than by every call site
/// independently picking a color that merely "looks pastel enough".
/// Deliberately gentle throughout: no neon, no heavily saturated tones,
/// nothing near-black — see `docs/` (or `AppTheme.floral`'s own doc
/// comment) for the design brief this follows.
class FloralPalette {
  FloralPalette._();

  static const pastelPink = Color(0xFFF7C6D9);
  static const blush = Color(0xFFF9D8DE);
  static const lavender = Color(0xFFD9CFEF);
  static const lilac = Color(0xFFE3D6F0);
  static const babyBlue = Color(0xFFCFE3F7);
  static const powderBlue = Color(0xFFC9E1EE);
  static const mint = Color(0xFFCDEEDD);
  static const sage = Color(0xFFD3E5D0);
  static const peach = Color(0xFFF9DCC4);
  static const softCoral = Color(0xFFF3C6C0);
  static const butterYellow = Color(0xFFF7ECC0);
  static const cream = Color(0xFFFBF3E7);

  /// A single, unified "ink" color for all text/icons in the Floral
  /// theme — one warm, muted dark tone rather than a different dark
  /// shade per surface, so typography reads as one deliberate system.
  /// Dark enough for real contrast against every pastel surface it's
  /// paired with below, never pure/harsh black.
  static const ink = Color(0xFF5B4249);

  /// A lighter step of [ink] for secondary/muted text (hints, captions,
  /// the outline role) — still clearly readable, just less emphatic than
  /// primary text.
  static const inkMuted = Color(0xFF8A6E76);

  /// The colors decorative flowers (see `FloralBackground`) are randomly
  /// drawn from — deliberately every pastel *except* [cream] (too close
  /// to the background to read as a flower at all) and [softCoral]
  /// (reserved for primary/buttons, so a flower landing near one doesn't
  /// visually blend into it).
  static const flowerColors = <Color>[
    pastelPink,
    blush,
    lavender,
    lilac,
    babyBlue,
    powderBlue,
    mint,
    sage,
    peach,
    butterYellow,
  ];
}

/// Tunable parameters for how `FloralBackground` scatters decorative
/// flowers — kept separate from the color palette above so "how many,
/// how big, how transparent" can be tuned without touching color
/// definitions, and vice versa.
class FloralFlowerConfig {
  FloralFlowerConfig._();

  /// How many flowers are scattered behind the app content.
  static const count = 10;

  /// Flowers stay subtle background texture, never competing with real
  /// UI content on top of them — see `AppTheme.floral`'s doc comment for
  /// the full reasoning. This is deliberately a narrow, low range.
  static const minOpacity = 0.08;
  static const maxOpacity = 0.18;

  /// Rendered size range, in logical pixels (the source SVG is square).
  static const minSize = 90.0;
  static const maxSize = 220.0;

  /// Rotation range, in degrees, applied per flower for an organic
  /// (non-grid-aligned) feel.
  static const minRotationDegrees = -30.0;
  static const maxRotationDegrees = 30.0;
}
