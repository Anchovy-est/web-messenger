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

/// Decrypts every chat's `lastMessage.body` in place — the chat list
/// preview reads from the exact same encrypted `messages.body`
/// column as the open thread (see backend/src/models/chat.model.js
/// `CHAT_SELECT`), so it needs the same treatment `ChatDetailController`
/// gives message history: this is the one place that treatment happens
/// for the *list* view, since `Chat` objects here are otherwise handed
/// straight from the repository to the UI. Chats with no message yet, or
/// whose last message is media (no inline body to decrypt), pass through
/// unchanged. A chat whose key can't be derived (no local identity yet,
/// or the other participant hasn't registered a public key) shows the
/// same placeholder an undecryptable message in an open thread would.
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

/// Backs the "Active" tab. Archiving a chat removes it from this list
/// locally (using the repository's response, not a guess) and — since
/// the Archived tab's controller may not even be alive yet if that tab
/// hasn't been opened — invalidates it so it fetches fresh whenever it
/// next is, rather than trying to splice state across two controllers
/// directly.
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
    // autoDispose + an await means this notifier may have been torn down
    // while the request was in flight (e.g. the Archived tab's own
    // refresh below disposing this one back, or the screen being popped)
    // — writing to `state` past that point throws, per StateNotifier.
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
