import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';

/// A thin, non-blocking banner shown at the top of an authenticated
/// screen whenever the realtime socket connection is down (no network,
/// or the server is unreachable). Renders nothing while connected.
///
/// REST calls (sending a message, editing a profile, etc.) don't depend
/// on this socket at all, so a drop here doesn't block any of them —
/// only realtime pushes (new messages, typing, delivery/read receipts)
/// are delayed until `socket.io`'s built-in reconnection succeeds, which
/// happens automatically with no action needed from the user. This
/// banner exists so that delay is visible instead of silent — a chat
/// that just looks quiet is indistinguishable from one where a reply
/// already arrived and simply hasn't been pushed down yet.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(socketConnectionStatusProvider);
    // Defaults to "connected" while the provider hasn't emitted yet
    // (effectively never, in practice — see the provider's own doc
    // comment) or on an unexpected stream error, so a transient glitch
    // reading connection state doesn't itself put up a false banner.
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
