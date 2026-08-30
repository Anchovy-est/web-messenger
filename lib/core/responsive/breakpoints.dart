import 'package:flutter/widgets.dart';

/// The app's window-size classes, loosely following Material 3's
/// guidance (compact/medium/expanded) — the one place screen-width
/// thresholds are decided, so every responsive branch in the app (the
/// navigation shell, the auth forms' width cap, …) agrees on the same
/// cutoffs instead of each picking its own magic number.
///
/// [compact] is exactly today's phone-sized single-column experience —
/// every existing mobile screen keeps rendering completely unchanged at
/// this size (see `AppShell`). [medium] and [expanded] both get the
/// persistent sidebar/master-detail desktop chrome; [expanded] additionally
/// gets a labeled (not just icon) sidebar, since there's room for it.
enum ScreenClass { compact, medium, expanded }

class Breakpoints {
  const Breakpoints._();

  /// Below this width: phone-style, single full-screen route at a time.
  /// Matches Material 3's compact/medium cutoff — comfortably wider than
  /// any phone in portrait, narrower than a split-view tablet or a
  /// desktop window.
  static const double compactMax = 700;

  /// Below this width (but at/above [compactMax]): desktop chrome, but
  /// an icon-only sidebar — a small laptop window or a tablet in
  /// landscape doesn't have room for full labels alongside a master-detail
  /// chat view.
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

  /// Today's unmodified single-screen-at-a-time mobile experience.
  bool get isCompact => screenClass == ScreenClass.compact;

  /// Persistent sidebar + master-detail desktop chrome (icon-only or
  /// labeled depending on [screenClass]).
  bool get isDesktop => !isCompact;

  bool get isExpanded => screenClass == ScreenClass.expanded;
}
