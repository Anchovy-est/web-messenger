import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decryption_placeholder.dart';
import '../../../models/chat.dart';
import '../../../providers/core_providers.dart';
import '../../../services/encryption_service.dart';
import '../../../services/secure_storage_service.dart';
import '../data/chat_providers.dart';
import '../data/chat_repository.dart';

/// Decrypts every chat's `lastMessage.body` in place. A chat with no
/// message, or media as its last message, passes through unchanged; one
/// whose key can't be derived shows the same undecryptable placeholder
/// an open thread would.
Future<List<Chat>> _decryptPreviews(
  List<Chat> chats,
  EncryptionService encryptionService,
  SecureStorageService secureStorage,
) async {
  final seed = await secureStorage.readIdentityPrivateKey();
  if (seed == null) return chats; // no local identity yet — nothing derivable
  final SimpleKeyPair myKeyPair;
  try {
    myKeyPair = await encryptionService.keyPairFromSeed(base64Decode(seed));
  } catch (_) {
    return chats;
  }
  return Future.wait(
    chats.map((chat) => _decryptPreview(chat, myKeyPair, encryptionService)),
  );
}

Future<Chat> _decryptPreview(
  Chat chat,
  SimpleKeyPair myKeyPair,
  EncryptionService encryptionService,
) async {
  final lastMessage = chat.lastMessage;
  if (lastMessage == null ||
      lastMessage.type != 'text' ||
      lastMessage.body == null) {
    return chat;
  }
  try {
    final key = await encryptionService.deriveChatKey(
      myKeyPair: myKeyPair,
      peerPublicKeyBase64: chat.otherParticipant?.publicKey,
      chatId: chat.id,
    );
    if (key == null) {
      return chat.copyWith(
        lastMessage: lastMessage.copyWith(body: undecryptableBodyPlaceholder),
      );
    }
    final plaintext = await encryptionService.decryptText(
      key,
      lastMessage.body!,
    );
    return chat.copyWith(lastMessage: lastMessage.copyWith(body: plaintext));
  } catch (_) {
    return chat.copyWith(
      lastMessage: lastMessage.copyWith(body: undecryptableBodyPlaceholder),
    );
  }
}

/// Backs the "Active" tab. Archiving removes the chat locally and
/// invalidates the Archived tab's controller so it refetches next time
/// it's opened.
class ActiveChatsController extends StateNotifier<AsyncValue<List<Chat>>> {
  ActiveChatsController(this._ref, this._repository)
    : _encryptionService = _ref.read(encryptionServiceProvider),
      _secureStorage = _ref.read(secureStorageServiceProvider),
      super(const AsyncValue.loading()) {
    refresh();
  }

  final Ref _ref;
  final ChatRepository _repository;
  final EncryptionService _encryptionService;
  final SecureStorageService _secureStorage;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final chats = await _repository.listChats(archived: false);
      return _decryptPreviews(chats, _encryptionService, _secureStorage);
    });
    // May have been disposed while the request was in flight.
    if (!mounted) return;
    state = result;
  }

  Future<void> archive(String chatId) async {
    await _repository.archive(chatId);
    if (!mounted) return;
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data([
        for (final chat in current)
          if (chat.id != chatId) chat,
      ]);
    }
    _ref.invalidate(archivedChatsControllerProvider);
  }
}

/// Backs the "Archived" tab — mirror image of [ActiveChatsController].
class ArchivedChatsController extends StateNotifier<AsyncValue<List<Chat>>> {
  ArchivedChatsController(this._ref, this._repository)
    : _encryptionService = _ref.read(encryptionServiceProvider),
      _secureStorage = _ref.read(secureStorageServiceProvider),
      super(const AsyncValue.loading()) {
    refresh();
  }

  final Ref _ref;
  final ChatRepository _repository;
  final EncryptionService _encryptionService;
  final SecureStorageService _secureStorage;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final chats = await _repository.listChats(archived: true);
      return _decryptPreviews(chats, _encryptionService, _secureStorage);
    });
    if (!mounted) return;
    state = result;
  }

  Future<void> unarchive(String chatId) async {
    await _repository.unarchive(chatId);
    if (!mounted) return;
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data([
        for (final chat in current)
          if (chat.id != chatId) chat,
      ]);
    }
    _ref.invalidate(activeChatsControllerProvider);
  }
}

final activeChatsControllerProvider =
    StateNotifierProvider.autoDispose<
      ActiveChatsController,
      AsyncValue<List<Chat>>
    >((ref) {
      return ActiveChatsController(ref, ref.watch(chatRepositoryProvider));
    });

final archivedChatsControllerProvider =
    StateNotifierProvider.autoDispose<
      ArchivedChatsController,
      AsyncValue<List<Chat>>
    >((ref) {
      return ArchivedChatsController(ref, ref.watch(chatRepositoryProvider));
    });
