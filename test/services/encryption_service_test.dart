// Pure crypto correctness tests for the end-to-end encryption service —
// no widget/platform dependency, since this is exercising `EncryptionService`
// directly. See backend/src/routes/message.routes.test.js for the
// equivalent proof from the *server's* side (using Node's own crypto
// primitives, to show the two independent implementations interoperate).
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
}
