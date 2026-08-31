import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when a ciphertext fails to decrypt — either genuinely tampered/
/// corrupted in transit, or (more likely in practice) encrypted with a
/// different key than the one being used to decrypt it, e.g. because the
/// other participant's identity key has changed since the message was
/// sent (a fresh install regenerates a fresh keypair — see
/// docs/ENCRYPTION.md for why that's an accepted trade-off of never
/// storing a plaintext key anywhere the server could recover it).
/// Callers are expected to catch this and show a clear "can't decrypt
/// this" placeholder rather than let it propagate as a crash.
class DecryptionFailedException implements Exception {
  const DecryptionFailedException();
}

/// True end-to-end encryption for message/media content: the
/// server (see backend/src/services/message.service.js) only ever stores
/// and relays opaque ciphertext it has no key to read.
///
/// Algorithm choices:
///  - **X25519** (Curve25519 Diffie-Hellman) for key agreement — every
///    user has one long-term identity keypair, generated on-device the
///    first time [SecureStorageService] has no stored private key yet;
///    the private half never leaves the device.
///  - **HKDF-SHA256** to turn the raw ECDH shared secret into a proper
///    AES key, salted per-chat so a compromised derived key for one chat
///    doesn't help derive another chat's key.
///  - **AES-256-GCM** (authenticated encryption) for the actual message/
///    media content — a tampered ciphertext fails to decrypt loudly (see
///    [DecryptionFailedException]) instead of silently producing
///    garbage.
///
/// Because this app's chats are always exactly two participants (see
/// backend/migrations/…init-chats-tables.js — nothing here creates a
/// group chat), a chat's encryption key never needs to be generated,
/// distributed, or stored *anywhere at all*: both participants
/// independently compute the identical key from (their own private key +
/// the other's public key) via ECDH, which is symmetric — Alice's-priv ·
/// Bob's-pub == Bob's-priv · Alice's-pub. Nothing about this key ever
/// crosses the network or touches the database. See docs/ENCRYPTION.md
/// for the full design writeup.
class EncryptionService {
  EncryptionService({X25519? keyExchangeAlgorithm, AesGcm? cipher})
    : _keyExchange = keyExchangeAlgorithm ?? X25519(),
      _cipher = cipher ?? AesGcm.with256bits();

  final X25519 _keyExchange;
  final AesGcm _cipher;

  // Distinguishes this key derivation from any unrelated future use of
  // HKDF in this codebase — standard practice for an HKDF "info" string,
  // not a secret.
  static const _hkdfInfo = 'mobile-messenger-chat-key-v1';
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// A fresh long-term identity keypair.
  Future<SimpleKeyPair> generateIdentityKeyPair() => _keyExchange.newKeyPair();

  /// Reconstructs a keypair from its stored private key bytes (the
  /// "seed" — for X25519 this *is* the raw 32-byte private scalar, so
  /// this is a cheap, purely-local operation, not a network round trip).
  Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) =>
      _keyExchange.newKeyPairFromSeed(seed);

  Future<List<int>> extractSeed(SimpleKeyPair keyPair) =>
      keyPair.extractPrivateKeyBytes();

  Future<String> exportPublicKey(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Derives this chat's AES-256-GCM key from my own identity keypair and
  /// the other participant's public key — see the class doc comment for
  /// why this never needs to be stored anywhere. Returns `null` if the
  /// other participant hasn't registered a public key yet (an account
  /// that predates this feature, or simply hasn't logged in since it
  /// shipped) — callers are expected to treat that as "encryption isn't
  /// available for this chat yet", not crash.
  Future<SecretKey?> deriveChatKey({
    required SimpleKeyPair myKeyPair,
    required String? peerPublicKeyBase64,
    required String chatId,
  }) async {
    if (peerPublicKeyBase64 == null) return null;
    final peerPublicKey = SimplePublicKey(
      base64Decode(peerPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(chatId), // HKDF's "salt" param — per-chat, not secret
      info: utf8.encode(_hkdfInfo),
    );
  }

  /// Encrypts UTF-8 text into a single base64 envelope — see
  /// docs/ENCRYPTION.md for the wire format, mirrored exactly by
  /// backend/src/utils/fieldCrypto.js on the server's own
  /// encrypted-*at-rest* tier (profile bio), though the two features
  /// never share a key.
  Future<String> encryptText(SecretKey key, String plaintext) async {
    final bytes = await encryptBytes(key, utf8.encode(plaintext));
    return base64Encode(bytes);
  }

  Future<String> decryptText(SecretKey key, String envelope) async {
    final bytes = await decryptBytes(key, base64Decode(envelope));
    return utf8.decode(bytes);
  }

  /// Encrypts arbitrary bytes (an image/video file) — same algorithm,
  /// same key; raw bytes out (nonce || ciphertext || tag) rather than
  /// base64, since this goes straight into a multipart upload body, not
  /// JSON.
  Future<Uint8List> encryptBytes(SecretKey key, List<int> plaintext) async {
    final secretBox = await _cipher.encrypt(plaintext, secretKey: key);
    return secretBox.concatenation();
  }

  Future<Uint8List> decryptBytes(SecretKey key, List<int> envelope) async {
    if (envelope.length < _nonceLength + _macLength) {
      throw const DecryptionFailedException();
    }
    final secretBox = SecretBox.fromConcatenation(
      envelope,
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    try {
      final plaintext = await _cipher.decrypt(secretBox, secretKey: key);
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      throw const DecryptionFailedException();
    }
  }

  // --- Group messaging ---------------------------------------------------
  //
  // A 1:1 chat's single [deriveChatKey] result works because ECDH between
  // exactly two people is symmetric (Alice-priv · Bob-pub == Bob-priv ·
  // Alice-pub) — there's no equivalent single shared secret for three or
  // more people without a real group key-agreement protocol (Signal's
  // Sender Keys, MLS, …), which is well beyond this app's scope. Instead,
  // a group message is encrypted once *per recipient*, each with that
  // recipient's own pairwise [deriveChatKey] result (same chatId salt,
  // so it's still a different key than any 1:1 chat the same two people
  // might separately have) — the caller (`ChatDetailController`) is
  // expected to include *every* current participant, itself included
  // (see its own doc comment on why: without a self-entry, a device
  // could never decrypt its own sent messages again after a reload).
  //
  // Text and media use the same wrap-per-recipient idea, just wrapping
  // different things: text wraps the plaintext itself directly; media
  // wraps a fresh one-time key instead (so the media bytes are only ever
  // encrypted *once*, not once per recipient — real savings once a
  // group's image/video messages are more than trivially sized).

  /// Encrypts [plaintext] once per entry in [recipientKeys] (participant
  /// user id -> this device's pairwise key with them) and returns the
  /// JSON-encoded `{userId: base64Envelope}` map — the wire format a
  /// group text message's `body` is sent/stored as, in place of the
  /// single envelope a 1:1 message's `body` is.
  Future<String> encryptTextForRecipients(
    Map<String, SecretKey> recipientKeys,
    String plaintext,
  ) async {
    final envelopes = <String, String>{};
    for (final entry in recipientKeys.entries) {
      envelopes[entry.key] = await encryptText(entry.value, plaintext);
    }
    return jsonEncode(envelopes);
  }

  /// The inverse of [encryptTextForRecipients] — decrypts just
  /// [myUserId]'s own entry, using [senderKey] (this device's pairwise
  /// key with whoever sent the message — *not* necessarily any key of
  /// mine, since the sender is the one who chose which key to encrypt
  /// each entry with). Returns `null`, not a thrown exception, when the
  /// map simply has no entry for [myUserId] at all — e.g. a message sent
  /// before this device joined the group, which was never wrapped for
  /// it in the first place; that's an expected case, distinct from
  /// [DecryptionFailedException] (an entry that exists but doesn't
  /// decrypt with the key given).
  Future<String?> decryptTextForRecipient({
    required String envelopeMapJson,
    required String myUserId,
    required SecretKey senderKey,
  }) async {
    final envelope = _ownEnvelope(envelopeMapJson, myUserId);
    if (envelope == null) return null;
    return decryptText(senderKey, envelope);
  }

  /// The media equivalent of [encryptTextForRecipients]: generates a
  /// fresh one-time key, encrypts [plaintext] (the actual image/video/
  /// audio bytes) with it exactly once, and separately wraps *that* key
  /// once per recipient the same way a text body's plaintext is wrapped
  /// directly. [encryptedBytes] is what gets uploaded as the message's
  /// media; [wrappedKeysJson] is what rides along as the message's
  /// `body` (otherwise unused for a media message) so each recipient can
  /// recover the one-time key and, in turn, the media itself.
  Future<({Uint8List encryptedBytes, String wrappedKeysJson})>
  encryptMediaForRecipients(
    Map<String, SecretKey> recipientKeys,
    Uint8List plaintext,
  ) async {
    final mediaKey = await _cipher.newSecretKey();
    final encryptedBytes = await encryptBytes(mediaKey, plaintext);
    final mediaKeyBytes = await mediaKey.extractBytes();

    final wrappedKeys = <String, String>{};
    for (final entry in recipientKeys.entries) {
      final wrapped = await encryptBytes(entry.value, mediaKeyBytes);
      wrappedKeys[entry.key] = base64Encode(wrapped);
    }
    return (
      encryptedBytes: encryptedBytes,
      wrappedKeysJson: jsonEncode(wrappedKeys),
    );
  }

  /// The inverse of [encryptMediaForRecipients]'s key-wrapping half —
  /// recovers the one-time media key bytes from [myUserId]'s own entry
  /// in the wrapped-keys map, decrypted with [senderKey]. The caller
  /// (`chat_media_content.dart`) turns the result into a [SecretKey] via
  /// `SecretKeyData` and uses *that* — not [senderKey] — to decrypt the
  /// downloaded media bytes. Same "missing entry is `null`, not an
  /// exception" contract as [decryptTextForRecipient].
  Future<Uint8List?> unwrapMediaKeyBytes({
    required String wrappedKeysJson,
    required String myUserId,
    required SecretKey senderKey,
  }) async {
    final wrapped = _ownEnvelope(wrappedKeysJson, myUserId);
    if (wrapped == null) return null;
    return decryptBytes(senderKey, base64Decode(wrapped));
  }

  String? _ownEnvelope(String envelopeMapJson, String myUserId) {
    final map = jsonDecode(envelopeMapJson) as Map<String, dynamic>;
    return map[myUserId] as String?;
  }
}
