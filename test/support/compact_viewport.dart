import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the test surface to a phone-sized (compact) window and restores
/// the default afterwards.
///
/// These tests pump the real [MessengerApp], including the real
/// `AppShell`, which renders differently once the window is wide enough
/// for the desktop sidebar — and the default test surface already
/// crosses that threshold. Pin to a width below `Breakpoints.compactMax`
/// so these phone-experience tests see a single `ChatListScreen`, no
/// sidebar.
void useCompactViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
