import 'package:flutter/material.dart';

/// "Something went wrong, here's a way to try again" — every screen that
/// loads data through an [AsyncValue] (chat list, chat detail,
/// invitations) used to define its own byte-for-byte identical version
/// of this. One shared widget instead — a future change to how errors
/// are presented (an icon, a different button style) is one edit, not a
/// find-and-replace across every screen.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
