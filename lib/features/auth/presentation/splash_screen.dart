import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/loading_view.dart';
import '../domain/session_state.dart';
import 'session_controller.dart';

/// Shown while [SessionController] restores a persisted session: a
/// plain spinner while checking, or a retryable error if the backend
/// couldn't be reached.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    if (session.status != SessionStatus.restoreFailed) {
      return const Scaffold(body: LoadingView());
    }

    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: colors.error),
              const SizedBox(height: 16),
              const Text(
                'Could not reach the server.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),
              // The specific reason, with a generic fallback.
              Text(
                session.restoreFailedMessage ??
                    'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.outline),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    ref.read(sessionControllerProvider.notifier).retryRestore(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
