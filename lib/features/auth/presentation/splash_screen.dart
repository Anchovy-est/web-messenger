import 'package:flutter/material.dart';

import '../../../widgets/loading_view.dart';

/// Shown only while [SessionController] is restoring a persisted session
/// at app startup (`SessionStatus.unknown`) — long enough to avoid a
/// login-screen flash for users who are already signed in.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView());
  }
}
