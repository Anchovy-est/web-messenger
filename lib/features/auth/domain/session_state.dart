import 'package:equatable/equatable.dart';

import '../../../models/user.dart';

enum SessionStatus {
  /// Still checking secure storage / calling the backend to see if a
  /// previously-saved session is still valid. The router shows a splash
  /// screen for this state instead of guessing which way to redirect.
  unknown,
  authenticated,
  unauthenticated,
}

class SessionState extends Equatable {
  const SessionState._(this.status, this.user);

  final SessionStatus status;
  final User? user;

  static const unknown = SessionState._(SessionStatus.unknown, null);
  static const unauthenticated = SessionState._(
    SessionStatus.unauthenticated,
    null,
  );

  factory SessionState.authenticated(User user) =>
      SessionState._(SessionStatus.authenticated, user);

  bool get isAuthenticated => status == SessionStatus.authenticated;

  @override
  List<Object?> get props => [status, user];
}
