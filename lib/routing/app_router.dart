import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/session_state.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/chats/presentation/chat_detail_screen.dart';
import '../features/chats/presentation/chat_list_screen.dart';
import '../features/invitations/presentation/invitations_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../models/user.dart';
import 'app_shell.dart';

/// Central route table, gated by [SessionController]'s state: `unknown`
/// shows the splash screen, `unauthenticated` forces /login,
/// `authenticated` forces away from /login and /register. Rebuilds the
/// whole router on a status change only (`.select`), not on every user
/// edit, so a profile update doesn't reset the nav stack.
final appRouterProvider = Provider<GoRouter>((ref) {
  final status = ref.watch(sessionControllerProvider.select((s) => s.status));

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      const authScreenPaths = {
        '/login',
        '/register',
        '/forgot-password',
        '/reset-password',
      };
      final goingToAuthScreen = authScreenPaths.contains(state.matchedLocation);

      switch (status) {
        case SessionStatus.unknown:
        case SessionStatus.restoreFailed:
          return null; // stay put; '/' renders the splash screen below.
        case SessionStatus.unauthenticated:
          return goingToAuthScreen ? null : '/login';
        case SessionStatus.authenticated:
          return goingToAuthScreen ? '/' : null;
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      // Every authenticated route is wrapped in one persistent
      // `AppShell` — unchanged on mobile, sidebar chrome on desktop/web.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(state: state, child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              if (status == SessionStatus.authenticated) {
                return const ChatListScreen();
              }
              return const SplashScreen();
            },
          ),
          GoRoute(
            path: '/verify-email',
            builder: (context, state) => const VerifyEmailScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/profile/edit',
            builder: (context, state) =>
                EditProfileScreen(user: state.extra as User),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: '/invitations',
            builder: (context, state) => const InvitationsScreen(),
          ),
          GoRoute(
            path: '/chats/:id',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return ChatDetailScreen(
                chatId: state.pathParameters['id']!,
                title: extra?['title'] as String?,
                avatarUrl: extra?['avatarUrl'] as String?,
              );
            },
          ),
        ],
      ),
    ],
  );
});
