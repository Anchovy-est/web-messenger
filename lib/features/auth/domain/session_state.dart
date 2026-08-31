import 'package:equatable/equatable.dart';

import '../../../models/user.dart';

enum SessionStatus {
  /// Still checking storage/the backend for a persisted session.
  unknown,
  authenticated,
  unauthenticated,

  /// A stored access token exists, but the backend couldn't be reached
  /// to confirm it's still valid — distinct from [unauthenticated]
  /// because only a confirmed rejection should ever clear the tokens
  /// and log someone out.
  restoreFailed,
}

class SessionState extends Equatable {
  const SessionState._(this.status, this.user, {this.restoreFailedMessage});

  final SessionStatus status;
  final User? user;

  /// Set alongside [SessionStatus.restoreFailed] — the actual error
  /// message, shown by [SplashScreen] instead of a generic one.
  final String? restoreFailedMessage;

  static const unknown = SessionState._(SessionStatus.unknown, null);
  static const unauthenticated = SessionState._(
    SessionStatus.unauthenticated,
    null,
  );

  factory SessionState.authenticated(User user) =>
      SessionState._(SessionStatus.authenticated, user);

  factory SessionState.restoreFailed(String message) => SessionState._(
    SessionStatus.restoreFailed,
    null,
    restoreFailedMessage: message,
  );

  bool get isAuthenticated => status == SessionStatus.authenticated;

  @override
  List<Object?> get props => [status, user, restoreFailedMessage];
}
