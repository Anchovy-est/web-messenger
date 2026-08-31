import 'package:flutter/material.dart';

/// Replaces Flutter's default error screen wherever a widget throws
/// while building — wired up via `ErrorWidget.builder` in `main()`.
/// Only the broken widget shows this; everything else keeps working.
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.errorContainer.withValues(alpha: 0.3),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: colors.error, size: 28),
              const SizedBox(height: 6),
              Text(
                'Something went wrong here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
