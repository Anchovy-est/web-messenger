import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';

/// A thin banner shown when the realtime socket is down. REST calls
/// aren't affected — only live pushes are delayed until socket.io
/// reconnects on its own.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(socketConnectionStatusProvider);
    // Defaults to "connected" so a transient read glitch doesn't show
    // a false banner.
    final isConnected = status.valueOrNull ?? true;
    if (isConnected) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No connection — reconnecting…',
                style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
