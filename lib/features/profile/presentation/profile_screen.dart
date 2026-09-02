import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/user_avatar.dart';
import '../../auth/presentation/session_controller.dart';

/// Displays the signed-in user's profile — reads straight from
/// [SessionController] rather than making its own network call.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final themeOption = ref.watch(themeControllerProvider);

    if (user == null) {
      // Shouldn't happen, but fail gracefully rather than crash.
      return const Scaffold(body: LoadingView());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            onPressed: () => context.push('/profile/edit', extra: user),
          ),
        ],
      ),
      body: SafeArea(
        // Width-capped so this doesn't stretch edge-to-edge on desktop.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: UserAvatar(avatarUrl: user.avatarUrl, radius: 56),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    user.username,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 32),
                Text('About Me', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(
                  (user.bio == null || user.bio!.isEmpty)
                      ? 'No bio yet.'
                      : user.bio!,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: (user.bio == null || user.bio!.isEmpty)
                        ? Theme.of(context).colorScheme.outline
                        : null,
                    fontStyle: (user.bio == null || user.bio!.isEmpty)
                        ? FontStyle.italic
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<AppThemeOption>(
                  segments: const [
                    ButtonSegment(
                      value: AppThemeOption.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: AppThemeOption.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: AppThemeOption.floral,
                      label: Text('Floral'),
                      icon: Icon(Icons.local_florist_outlined),
                    ),
                  ],
                  selected: {themeOption},
                  onSelectionChanged: (selected) => ref
                      .read(themeControllerProvider.notifier)
                      .setOption(selected.first),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
