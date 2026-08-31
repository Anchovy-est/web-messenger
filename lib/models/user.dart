import 'package:equatable/equatable.dart';

/// The public user shape returned by the backend — never a password or
/// anything else sensitive.
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

  /// This account's end-to-end encryption public key.
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
