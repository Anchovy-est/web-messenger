import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/loading_view.dart';
import '../domain/session_state.dart';
import 'session_controller.dart';

/// Shown while [SessionController] is restoring a persisted session at
/// app startup, for both of the two states that can mean: a plain
/// loading spinner for `SessionStatus.unknown` (still checking — long
/// enough to avoid a login-screen flash for someone who's already
/// signed in), and a retryable error for `SessionStatus.restoreFailed`
/// (a stored session exists, but the backend couldn't be reached to
/// confirm it's still valid — see that status's own doc comment for why
/// this is deliberately *not* the same as being logged out).
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
              // The specific reason (e.g. "The service is temporarily
              // unavailable." vs. a plain timeout) — see
              // `SessionState.restoreFailedMessage`'s doc comment — with
              // a generic fallback for the unlikely case this state was
              // somehow reached without one.
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
