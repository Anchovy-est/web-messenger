import 'package:flutter/widgets.dart';

/// The app's window-size classes (compact/medium/expanded), loosely
/// following Material 3. [compact] is today's single-column phone
/// layout; [medium]/[expanded] get the desktop sidebar, with
/// [expanded] adding labels.
enum ScreenClass { compact, medium, expanded }

class Breakpoints {
  const Breakpoints._();

  /// Below this: phone-style, one screen at a time.
  static const double compactMax = 700;

  /// Below this (but at/above [compactMax]): desktop chrome with an
  /// icon-only sidebar.
  static const double mediumMax = 1100;

  static ScreenClass classify(double width) {
    if (width < compactMax) return ScreenClass.compact;
    if (width < mediumMax) return ScreenClass.medium;
    return ScreenClass.expanded;
  }

  static ScreenClass of(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width);
}

extension ResponsiveContext on BuildContext {
  ScreenClass get screenClass => Breakpoints.of(this);

  bool get isCompact => screenClass == ScreenClass.compact;

  /// Desktop sidebar + master-detail chrome.
  bool get isDesktop => !isCompact;

  bool get isExpanded => screenClass == ScreenClass.expanded;
}
