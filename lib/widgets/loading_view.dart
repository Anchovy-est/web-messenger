import 'package:flutter/material.dart';

/// A full-screen/section "still loading" state — a centered spinner,
/// nothing else. Every screen that loads data through an [AsyncValue]
/// (chat list, chat detail, invitations, search, the splash screen) used
/// to repeat `Center(child: CircularProgressIndicator())` independently;
/// one shared widget means they all look the same by construction, and
/// a future change (e.g. a "Loading…" caption) is one edit instead of
/// several.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
