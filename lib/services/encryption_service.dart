import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when a ciphertext fails to decrypt — tampered, or encrypted
/// with a different key (e.g. the sender's identity key changed).
/// Callers should show a "can't decrypt this" placeholder, not crash.
class DecryptionFailedException implements Exception {
  const DecryptionFailedException();
}

/// End-to-end encryption for message/media content — the server only
/// ever stores and relays ciphertext it has no key to read.
///
/// X25519 for key agreement (one long-term identity keypair per user,
/// private half never leaves the device), HKDF-SHA256 to turn the ECDH
/// secret into an AES key salted per chat, AES-256-GCM for the actual
/// content (a tampered ciphertext fails loudly, not silently).
///
/// A 1:1 chat's key is never stored anywhere: both sides independently
/// derive the identical key via ECDH (Alice-priv · Bob-pub == Bob-priv
/// · Alice-pub).
class EncryptionService {
  EncryptionService({X25519? keyExchangeAlgorithm, AesGcm? cipher})
    : _keyExchange = keyExchangeAlgorithm ?? X25519(),
      _cipher = cipher ?? AesGcm.with256bits();

  final X25519 _keyExchange;
  final AesGcm _cipher;

  static const _hkdfInfo = 'mobile-messenger-chat-key-v1';
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// A fresh long-term identity keypair.
  Future<SimpleKeyPair> generateIdentityKeyPair() => _keyExchange.newKeyPair();

  /// Reconstructs a keypair from its stored seed — a local, no-network
  /// operation.
  Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) =>
      _keyExchange.newKeyPairFromSeed(seed);

  Future<List<int>> extractSeed(SimpleKeyPair keyPair) =>
      keyPair.extractPrivateKeyBytes();

  Future<String> exportPublicKey(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Derives this chat's AES-256-GCM key from my keypair and the
  /// peer's public key. Returns null if the peer hasn't registered a
  /// public key yet — callers treat that as "not available yet".
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
      nonce: utf8.encode(chatId), // HKDF salt — per-chat, not secret
      info: utf8.encode(_hkdfInfo),
    );
  }

  /// Encrypts UTF-8 text into a single base64 envelope.
  Future<String> encryptText(SecretKey key, String plaintext) async {
    final bytes = await encryptBytes(key, utf8.encode(plaintext));
    return base64Encode(bytes);
  }

  Future<String> decryptText(SecretKey key, String envelope) async {
    final bytes = await decryptBytes(key, base64Decode(envelope));
    return utf8.decode(bytes);
  }

  /// Encrypts raw bytes (an image/video) — nonce || ciphertext || tag,
  /// for a multipart upload body rather than JSON.
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

  // --- Group messaging -----------------------------------------------
  //
  // No single shared secret exists for 3+ people without a real group
  // key-agreement protocol, so a group message is encrypted once per
  // recipient with that recipient's own pairwise key (including a
  // self-entry, so a device can still decrypt its own sent messages).
  // Media wraps a fresh one-time key per recipient instead of
  // re-encrypting the whole file for each one.

  /// Encrypts [plaintext] once per entry in [recipientKeys] and returns
  /// the JSON `{userId: base64Envelope}` map a group message's `body`
  /// is sent/stored as.
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

  /// Decrypts just [myUserId]'s entry with [senderKey]. Returns null
  /// (not an exception) if there's no entry at all — e.g. a message
  /// sent before this device joined the group.
  Future<String?> decryptTextForRecipient({
    required String envelopeMapJson,
    required String myUserId,
    required SecretKey senderKey,
  }) async {
    final envelope = _ownEnvelope(envelopeMapJson, myUserId);
    if (envelope == null) return null;
    return decryptText(senderKey, envelope);
  }

  /// Media version of [encryptTextForRecipients]: generates a one-time
  /// key, encrypts the media once with it, then wraps that key once
  /// per recipient. [encryptedBytes] gets uploaded; [wrappedKeysJson]
  /// rides along as the message body.
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

  /// Recovers the one-time media key from [myUserId]'s entry, decrypted
  /// with [senderKey]. Same null-if-missing contract as
  /// [decryptTextForRecipient].
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
