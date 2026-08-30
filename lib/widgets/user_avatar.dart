import 'package:flutter/material.dart';

import '../core/media_url.dart';

/// A user's profile picture, or a generic placeholder when they don't
/// have one set, or when the image fails to load (stale URL, network
/// hiccup, deleted file). Reused wherever a user is shown: profile
/// screen, search results, chat list/messages.
class UserAvatar extends StatefulWidget {
  const UserAvatar({super.key, required this.avatarUrl, this.radius = 40});

  final String? avatarUrl;
  final double radius;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _failedToLoad = false;

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new URL (e.g. after uploading a replacement avatar) deserves a
    // fresh attempt rather than staying stuck on a previous failure.
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
          // Falls back to the placeholder below instead of leaving a
          // blank circle (CircleAvatar doesn't do this on its own) or
          // letting the load exception go uncaught.
          if (mounted) setState(() => _failedToLoad = true);
        },
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Icon(
        Icons.person,
        size: widget.radius,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}
