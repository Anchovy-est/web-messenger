import 'package:flutter/material.dart';

/// Shared shape for every auth screen's scrollable form — caps the
/// width on a wide window so fields don't stretch edge-to-edge; no
/// effect on phone-sized windows.
class ResponsiveFormScaffold extends StatelessWidget {
  const ResponsiveFormScaffold({
    super.key,
    required this.appBar,
    required this.child,
    this.maxWidth = 480,
  });

  final PreferredSizeWidget appBar;

  /// The form content — typically a `Form` wrapping a `Column`.
  final Widget child;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
