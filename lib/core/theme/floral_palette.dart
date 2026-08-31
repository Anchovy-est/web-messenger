import 'package:flutter/material.dart';

/// The Floral theme's curated pastel palette — every Floral color comes
/// from here. Deliberately gentle: no neon, nothing near-black.
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

  /// One warm, muted dark tone for all text/icons in this theme.
  static const ink = Color(0xFF5B4249);

  /// A lighter step of [ink] for secondary/muted text.
  static const inkMuted = Color(0xFF8A6E76);

  /// Colors decorative flowers are drawn from — every pastel except
  /// [cream] (blends into the background) and [softCoral] (reserved
  /// for buttons).
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

/// Tunable parameters for how `FloralBackground` scatters flowers.
class FloralFlowerConfig {
  FloralFlowerConfig._();

  static const count = 10;

  /// Kept subtle so flowers never compete with real UI content.
  static const minOpacity = 0.08;
  static const maxOpacity = 0.18;

  /// Rendered size range, in logical pixels.
  static const minSize = 90.0;
  static const maxSize = 220.0;

  /// Rotation range, in degrees, for an organic feel.
  static const minRotationDegrees = -30.0;
  static const maxRotationDegrees = 30.0;
}
