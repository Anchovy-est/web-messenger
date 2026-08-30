import 'package:equatable/equatable.dart';

/// Mirrors the public user shape returned by the backend
/// (see backend/src/models/user.model.js `toPublicUser`) — never carries
/// a password or anything else sensitive.
class User extends Equatable {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.emailVerified,
    this.avatarUrl,
    this.bio,
    this.publicKey,
  });

  final String id;
  final String username;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final bool emailVerified;

  /// This account's end-to-end encryption public key, on whichever
  /// device most recently registered one — see
  /// lib/services/encryption_service.dart. Not used for anything on
  /// *my own* [User] object client-side (I always use my own locally-held
  /// private key directly); present here mainly because the backend
  /// returns it on every user payload and it costs nothing to carry.
  final String? publicKey;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String? ?? json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      publicKey: json['publicKey'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    email,
    displayName,
    avatarUrl,
    bio,
    publicKey,
    emailVerified,
  ];
}
