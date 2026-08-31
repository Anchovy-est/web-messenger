import 'package:equatable/equatable.dart';

import '../../../models/user.dart';

enum SessionStatus {
  /// Still checking secure storage / calling the backend to see if a
  /// previously-saved session is still valid. The router shows a splash
  /// screen for this state instead of guessing which way to redirect.
  unknown,
  authenticated,
  unauthenticated,

  /// A stored access token exists, but `SessionController._restore`
  /// couldn't reach the backend to confirm whether it's still valid
  /// (no network, the server's down/unreachable, a timeout, or a 5xx —
  /// see `_restore`'s own doc comment for exactly which failures land
  /// here vs. [unauthenticated]). Deliberately distinct from
  /// [unauthenticated]: the difference is the whole point of this
  /// state, since only a *confirmed* rejection (a definitive 401 the
  /// backend actually returned) should ever clear the stored tokens and
  /// send someone back to the login form. A transient failure to reach
  /// the server must never masquerade as "you're logged out" — that
  /// would destroy a perfectly good session over what might just be a
  /// dropped wifi connection.
  restoreFailed,
}

class SessionState extends Equatable {
  const SessionState._(this.status, this.user, {this.restoreFailedMessage});

  final SessionStatus status;
  final User? user;

  /// Only ever set alongside [SessionStatus.restoreFailed] — the actual
  /// `ApiException.message` that failed to confirm the stored session
  /// (see `SessionController._restore`), shown by [SplashScreen] instead
  /// of a one-size-fits-all string so "no network", "the server is
  /// down", and "the database is unavailable" each read as what they
  /// actually are, the same way every other screen's error text does
  /// (e.g. `ErrorStateView`).
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
