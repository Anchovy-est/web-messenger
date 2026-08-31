import 'package:flutter/material.dart';

/// Opens [child] — an existing full-screen routed screen, unmodified —
/// as a centered desktop dialog. Used by `AppShell`'s sidebar for
/// quick-access destinations (Search, Invitations) that don't need the
/// whole content pane.
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
