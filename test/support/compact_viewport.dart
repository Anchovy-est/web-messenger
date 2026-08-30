import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the test surface to a phone-sized (compact) window and restores
/// the default afterwards.
///
/// These end-to-end tests pump the real [MessengerApp] — including the
/// real `appRouterProvider` and, once authenticated, the real `AppShell`
/// — rather than a screen in isolation. `AppShell` renders differently
/// once the window is wide enough for the desktop sidebar/master-detail
/// chrome (see `lib/core/responsive/breakpoints.dart`), and the default
/// test surface (800×600) already crosses that threshold. Since these
/// specific tests are about the phone experience (matching what they
/// assert — a single `ChatListScreen`, no sidebar), pin them to a width
/// below `Breakpoints.compactMax` so `AppShell` renders exactly what it
/// did before it existed, regardless of what the default test surface
/// size happens to be.
void useCompactViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
