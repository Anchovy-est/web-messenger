import 'package:flutter/material.dart';

/// Shared "still loading" state — a centered spinner, nothing else.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
