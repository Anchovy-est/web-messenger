import 'package:flutter/material.dart';

/// "There's nothing here yet" — a centered, muted message, with an
/// optional icon above it. Used for an empty chat list, no invitations,
/// no search results, an empty thread, and so on.
///
/// Several screens used to each define their own near-identical version
/// of this (one with an icon, one without, one missing the padding/
/// center-alignment the others had) — collapsing them into one widget
/// means every empty state in the app genuinely looks the same, not just
/// similar.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
