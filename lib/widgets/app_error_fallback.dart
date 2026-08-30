import 'package:flutter/material.dart';

/// Replaces Flutter's default red/grey "error screen" wherever a widget
/// throws while building, laying out, or painting — wired up once, in
/// `main()`, via `ErrorWidget.builder`. Flutter already scopes a thrown
/// build error to just the widget that threw (its siblings, the rest of
/// the screen, navigation — all keep working normally), so showing a
/// small, calm fallback here rather than Flutter's own error widget
/// (which is minimal/blank in release builds, and alarming in debug
/// ones) is what actually delivers "reloads to the last stable state"
/// with visible feedback, not a crash: the one broken widget shows this
/// instead of dying loudly, everything around it is unaffected.
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
