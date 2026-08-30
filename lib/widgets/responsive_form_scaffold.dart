import 'package:flutter/material.dart';

/// Every auth screen (login, register, forgot/reset password, verify
/// email) is a single scrollable form on an [AppBar]d [Scaffold] — this
/// wraps that shared shape once so a wide (desktop/web) window shows a
/// comfortably narrow, centered card instead of a form with its text
/// fields and buttons stretched edge-to-edge across the whole browser
/// window. Below [maxWidth] (i.e. every phone, and this app's whole mobile
/// experience) the constraint never actually binds, so this renders
/// pixel-identical to the plain `SingleChildScrollView` these screens used
/// before — nothing about the mobile layout changes.
class ResponsiveFormScaffold extends StatelessWidget {
  const ResponsiveFormScaffold({
    super.key,
    required this.appBar,
    required this.child,
    this.maxWidth = 480,
  });

  final PreferredSizeWidget appBar;

  /// The form content — typically a `Form` wrapping a `Column`, exactly
  /// what each screen's body used to hand straight to
  /// `SingleChildScrollView`.
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
