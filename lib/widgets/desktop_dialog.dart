import 'package:flutter/material.dart';

/// Opens [child] — one of the app's existing full-screen routed screens,
/// completely unmodified — as a centered desktop dialog instead. Used by
/// `AppShell`'s sidebar for quick-access destinations (Search,
/// Invitations) that don't need to occupy the whole content pane: a
/// desktop messenger surfaces those as an overlay panel, not a full page
/// swap (see e.g. Telegram Desktop's search, Slack's activity panel).
///
/// [child]'s own `AppBar` back arrow closes this exactly like it would
/// pop a pushed route — `showDialog` pushes onto the same `Navigator`, so
/// `Navigator.canPop`/`pop` behave the same way here as they do for an
/// actually-pushed screen; nothing about the screen itself needs to know
/// it's in a dialog.
Future<void> showDesktopDialog(
  BuildContext context, {
  required Widget child,
  double width = 480,
  double height = 640,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: width, height: height, child: child),
    ),
  );
}
