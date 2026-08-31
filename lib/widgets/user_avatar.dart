import 'package:flutter/material.dart';

import '../core/media_url.dart';

/// A user's profile picture, or a generic placeholder when there isn't
/// one (or it fails to load). Reused wherever a user is shown.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 40,
    this.placeholderIcon = Icons.person,
  });

  final String? avatarUrl;
  final double radius;

  /// Defaults to a person icon; a group chat passes `Icons.groups`.
  final IconData placeholderIcon;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _failedToLoad = false;

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new URL deserves a fresh attempt, not a stuck old failure.
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _failedToLoad = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.avatarUrl;
    if (url != null && url.isNotEmpty && !_failedToLoad) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: NetworkImage(resolveMediaUrl(url)),
        onBackgroundImageError: (exception, stackTrace) {
          // Falls back to the placeholder instead of a blank circle.
          if (mounted) setState(() => _failedToLoad = true);
        },
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Icon(
        widget.placeholderIcon,
        size: widget.radius,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}
