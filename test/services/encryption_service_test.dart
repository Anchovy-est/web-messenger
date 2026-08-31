// Pure crypto correctness tests for the end-to-end encryption service —
// no widget/platform dependency, since this is exercising `EncryptionService`
// directly. See backend/src/routes/message.routes.test.js for the
// equivalent proof from the *server's* side (using Node's own crypto
// primitives, to show the two independent implementations interoperate).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

import 'package:mobile_messenger/services/encryption_service.dart';

void main() {
  late EncryptionService service;

  setUp(() {
    service = EncryptionService();
  });

  test(
    'two independently-generated keypairs derive the identical chat key via ECDH',
    () async {
      final alice = await service.generateIdentityKeyPair();
      final bob = await service.generateIdentityKeyPair();
      final alicePublic = await service.exportPublicKey(alice);
      final bobPublic = await service.exportPublicKey(bob);

      final aliceKey = await service.deriveChatKey(
        myKeyPair: alice,
        peerPublicKeyBase64: bobPublic,
        chatId: 'chat-1',
      );
      final bobKey = await service.deriveChatKey(
        myKeyPair: bob,
        peerPublicKeyBase64: alicePublic,
        chatId: 'chat-1',
      );

      final aliceBytes = await aliceKey!.extractBytes();
      final bobBytes = await bobKey!.extractBytes();
      expect(aliceBytes, bobBytes);
    },
  );

  test(
    'deriving a key for a different chat id produces a different key',
    () async {
      final alice = await service.generateIdentityKeyPair();
      final bob = await service.generateIdentityKeyPair();
      final bobPublic = await service.exportPublicKey(bob);

      final key1 = await service.deriveChatKey(
        myKeyPair: alice,
        peerPublicKeyBase64: bobPublic,
        chatId: 'chat-1',
      );
      final key2 = await service.deriveChatKey(
        myKeyPair: alice,
        peerPublicKeyBase64: bobPublic,
        chatId: 'chat-2',
      );

      expect(
        await key1!.extractBytes(),
        isNot(equals(await key2!.extractBytes())),
      );
    },
  );

  test(
    'deriveChatKey returns null when the peer has no public key yet',
    () async {
      final alice = await service.generateIdentityKeyPair();

      final key = await service.deriveChatKey(
        myKeyPair: alice,
        peerPublicKeyBase64: null,
        chatId: 'chat-1',
      );

      expect(key, isNull);
    },
  );

  test(
    'a keypair reconstructed from its stored seed derives the same key as the original',
    () async {
      final alice = await service.generateIdentityKeyPair();
      final bob = await service.generateIdentityKeyPair();
      final bobPublic = await service.exportPublicKey(bob);

      final seed = await service.extractSeed(alice);
      final restoredAlice = await service.keyPairFromSeed(seed);

      final originalKey = await service.deriveChatKey(
        myKeyPair: alice,
        peerPublicKeyBase64: bobPublic,
        chatId: 'chat-1',
      );
      final restoredKey = await service.deriveChatKey(
        myKeyPair: restoredAlice,
        peerPublicKeyBase64: bobPublic,
        chatId: 'chat-1',
      );

      expect(
        await originalKey!.extractBytes(),
        await restoredKey!.extractBytes(),
      );
    },
  );

  test('text round-trips through encrypt then decrypt', () async {
    final key = SecretKey(List.generate(32, (i) => i));
    const plaintext = 'Meet me at midnight — don\'t tell anyone.';

    final envelope = await service.encryptText(key, plaintext);
    final decrypted = await service.decryptText(key, envelope);

    expect(decrypted, plaintext);
    expect(envelope, isNot(contains(plaintext)));
  });

  test('bytes round-trip through encrypt then decrypt', () async {
    final key = SecretKey(List.generate(32, (i) => i));
    final plaintext = List.generate(500, (i) => i % 256);

    final envelope = await service.encryptBytes(key, plaintext);
    final decrypted = await service.decryptBytes(key, envelope);

    expect(decrypted, plaintext);
  });

  test(
    'decrypting with the wrong key throws DecryptionFailedException',
    () async {
      final key = SecretKey(List.generate(32, (i) => i));
      final wrongKey = SecretKey(List.generate(32, (i) => 255 - i));
      final envelope = await service.encryptText(key, 'secret');

      expect(
        () => service.decryptText(wrongKey, envelope),
        throwsA(isA<DecryptionFailedException>()),
      );
    },
  );

  test(
    'decrypting a tampered envelope throws DecryptionFailedException',
    () async {
      final key = SecretKey(List.generate(32, (i) => i));
      final envelope = await service.encryptBytes(key, 'secret'.codeUnits);
      envelope[envelope.length - 1] ^= 0xFF; // flip a bit in the auth tag

      expect(
        () => service.decryptBytes(key, envelope),
        throwsA(isA<DecryptionFailedException>()),
      );
    },
  );

  test(
    'decrypting a too-short envelope throws DecryptionFailedException',
    () async {
      final key = SecretKey(List.generate(32, (i) => i));

      expect(
        () => service.decryptBytes(key, [1, 2, 3]),
        throwsA(isA<DecryptionFailedException>()),
      );
    },
  );

  // --- Group messaging: per-recipient wrapping ----------------------------

  test(
    'encryptTextForRecipients wraps the same plaintext separately for every recipient, each independently decryptable',
    () async {
      final aliceKey = SecretKey(List.generate(32, (i) => i)); // "me"
      final bobKey = SecretKey(List.generate(32, (i) => i + 1));
      final carolKey = SecretKey(List.generate(32, (i) => i + 2));
      const plaintext = 'meeting moved to 5pm';

      final envelopeMap = await service.encryptTextForRecipients({
        'alice': aliceKey,
        'bob': bobKey,
        'carol': carolKey,
      }, plaintext);

      // Opaque on the wire — the plaintext never appears verbatim.
      expect(envelopeMap, isNot(contains(plaintext)));

      for (final MapEntry(key: userId, value: key) in {
        'alice': aliceKey,
        'bob': bobKey,
        'carol': carolKey,
      }.entries) {
        final decrypted = await service.decryptTextForRecipient(
          envelopeMapJson: envelopeMap,
          myUserId: userId,
          senderKey: key,
        );
        expect(decrypted, plaintext);
      }
    },
  );

  test(
    'decryptTextForRecipient returns null (not an exception) for a user with no entry in the map',
    () async {
      final aliceKey = SecretKey(List.generate(32, (i) => i));
      final envelopeMap = await service.encryptTextForRecipients({
        'alice': aliceKey,
      }, 'hello');

      final result = await service.decryptTextForRecipient(
        envelopeMapJson: envelopeMap,
        myUserId: 'dave', // never invited, never wrapped for
        senderKey: aliceKey,
      );

      expect(result, isNull);
    },
  );

  test(
    'decryptTextForRecipient throws DecryptionFailedException for a present entry that just does not decrypt with the given key',
    () async {
      final aliceKey = SecretKey(List.generate(32, (i) => i));
      final wrongKey = SecretKey(List.generate(32, (i) => 255 - i));
      final envelopeMap = await service.encryptTextForRecipients({
        'alice': aliceKey,
      }, 'hello');

      expect(
        () => service.decryptTextForRecipient(
          envelopeMapJson: envelopeMap,
          myUserId: 'alice',
          senderKey: wrongKey,
        ),
        throwsA(isA<DecryptionFailedException>()),
      );
    },
  );

  test(
    'encryptMediaForRecipients encrypts the media once and wraps a recoverable one-time key per recipient',
    () async {
      final aliceKey = SecretKey(List.generate(32, (i) => i));
      final bobKey = SecretKey(List.generate(32, (i) => i + 1));
      final mediaBytes = Uint8List.fromList(
        List.generate(1000, (i) => i % 256),
      );

      final result = await service.encryptMediaForRecipients({
        'alice': aliceKey,
        'bob': bobKey,
      }, mediaBytes);

      // The media itself is genuinely encrypted (not just re-shaped).
      expect(result.encryptedBytes, isNot(equals(mediaBytes)));

      for (final MapEntry(key: userId, value: key) in {
        'alice': aliceKey,
        'bob': bobKey,
      }.entries) {
        final unwrapped = await service.unwrapMediaKeyBytes(
          wrappedKeysJson: result.wrappedKeysJson,
          myUserId: userId,
          senderKey: key,
        );
        expect(unwrapped, isNotNull);
        final decrypted = await service.decryptBytes(
          SecretKey(unwrapped!),
          result.encryptedBytes,
        );
        expect(decrypted, mediaBytes);
      }
    },
  );

  test(
    'unwrapMediaKeyBytes returns null for a user with no entry in the wrapped-keys map',
    () async {
      final aliceKey = SecretKey(List.generate(32, (i) => i));
      final result = await service.encryptMediaForRecipients({
        'alice': aliceKey,
      }, Uint8List.fromList([1, 2, 3]));

      final unwrapped = await service.unwrapMediaKeyBytes(
        wrappedKeysJson: result.wrappedKeysJson,
        myUserId: 'dave',
        senderKey: aliceKey,
      );

      expect(unwrapped, isNull);
    },
  );

  test(
    'a self-derived key (deriveChatKey against my own public key) lets a device decrypt its own wrapped entry',
    () async {
      // This is exactly what `ChatDetailController` relies on to let a
      // device read its own past group messages after a reload — every
      // recipient map it builds includes an entry for itself, wrapped
      // with a key derived against its own public key rather than a
      // peer's.
      final me = await service.generateIdentityKeyPair();
      final myPublicKey = await service.exportPublicKey(me);
      final selfKey = await service.deriveChatKey(
        myKeyPair: me,
        peerPublicKeyBase64: myPublicKey,
        chatId: 'group-1',
      );

      expect(selfKey, isNotNull);
      final envelopeMap = await service.encryptTextForRecipients({
        'me': selfKey!,
      }, 'note to self');
      final decrypted = await service.decryptTextForRecipient(
        envelopeMapJson: envelopeMap,
        myUserId: 'me',
        senderKey: selfKey,
      );
      expect(decrypted, 'note to self');
    },
  );
}
