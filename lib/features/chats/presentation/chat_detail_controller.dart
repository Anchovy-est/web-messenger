import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/decryption_placeholder.dart';
import '../../../models/message.dart';
import '../../../models/message_status_update.dart';
import '../../../models/poll.dart';
import '../../../models/poll_update.dart';
import '../../../providers/core_providers.dart';
import '../../../services/encryption_service.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/socket_service.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/chat_providers.dart';
import '../data/chat_repository.dart';
import '../data/message_repository.dart';
import '../data/poll_repository.dart';

/// How long the composer can sit idle before we tell the other side
/// we've stopped typing, if [ChatDetailController.onComposerChanged]
/// doesn't fire again first.
const _typingStopDelay = Duration(seconds: 3);

/// Backs a single chat's message thread. One instance per chat — loads
/// history on creation, then merges in `message:new`/`message:status`
/// pushes from the socket. Messages are always sent over REST; the
/// socket only adds to the list, de-duped by id (a sent message is
/// appended locally from the REST response, then echoed back down the
/// socket to every participant including the sender).
///
/// Sending is optimistic: a local placeholder appears immediately, then
/// becomes the server-confirmed message or, on failure, `failed` — with
/// [retry] to try again in place.
///
/// Also sends this chat's typing indicator (receiving is a separate
/// concern — see `TypingIndicatorController`), and owns this chat's
/// end-to-end encryption. Every `Message` in [state] has an
/// already-decrypted plaintext `body` — media is different: `mediaUrl`
/// stays as ciphertext on disk, decrypted lazily only when a bubble
/// renders it, via [keyForSender].
///
/// A 1:1 chat has one shared key both sides derive independently; a
/// group has no single shared secret, so each message is wrapped once
/// per recipient instead (see [_groupKeys]).
class ChatDetailController extends StateNotifier<AsyncValue<List<Message>>> {
  ChatDetailController(
    this._ref,
    this._chatId,
    this._repository,
    this._chatRepository,
    this._pollRepository,
    this._encryptionService,
  ) : _socketService = _ref.read(socketServiceProvider),
      _secureStorage = _ref.read(secureStorageServiceProvider),
      super(const AsyncValue.loading()) {
    _messageSubscription = _socketService.messageStream.listen(_onIncoming);
    _statusSubscription = _socketService.statusStream.listen(_onStatus);
    _editedSubscription = _socketService.editedMessageStream.listen(_onEdited);
    _deletedSubscription = _socketService.deletedMessageStream.listen(
      _onDeleted,
    );
    _pollUpdatedSubscription = _socketService.pollUpdatedStream.listen(
      _onPollUpdated,
    );
    _init();
  }

  final Ref _ref;
  final String _chatId;
  final MessageRepository _repository;
  final ChatRepository _chatRepository;
  final PollRepository _pollRepository;
  final EncryptionService _encryptionService;
  final SocketService _socketService;
  final SecureStorageService _secureStorage;
  late final StreamSubscription<Message> _messageSubscription;
  late final StreamSubscription<MessageStatusUpdate> _statusSubscription;
  late final StreamSubscription<Message> _editedSubscription;
  late final StreamSubscription<Message> _deletedSubscription;
  late final StreamSubscription<PollUpdate> _pollUpdatedSubscription;
  int _tempIdCounter = 0;
  Timer? _typingStopTimer;
  bool _iAmTyping = false;

  /// This chat's derived AES-256-GCM key — only set for a 1:1 chat.
  /// Null if this device has no identity keypair yet, the peer hasn't
  /// registered a public key, or this is a group chat (see
  /// [_groupKeys] instead).
  SecretKey? _chatKey;

  /// This device's pairwise key with each other participant of a group
  /// chat, including a self-entry (derived against its own public
  /// key) — without it, a device could never decrypt its own sent
  /// messages again after a reload. Empty for a 1:1 chat.
  Map<String, SecretKey> _groupKeys = {};

  bool _isGroup = false;

  /// Whether this chat is a group.
  bool get isGroup => _isGroup;

  /// Every other group participant's display name, by user id. Empty
  /// for a 1:1 chat.
  Map<String, String> _participantNames = {};
  Map<String, String> get participantNames => _participantNames;

  /// The key to decrypt something [senderId] encrypted — [_chatKey] for
  /// a 1:1 chat, or [senderId]'s own entry in [_groupKeys] for a group.
  SecretKey? keyForSender(String? senderId) {
    if (!_isGroup) return _chatKey;
    if (senderId == null) return null;
    return _groupKeys[senderId];
  }

  bool get _encryptionReady =>
      _isGroup ? _groupKeys.isNotEmpty : _chatKey != null;

  Future<void> _init() async {
    await _prepareEncryption();
    await refresh();
  }

  Future<void> _prepareEncryption() async {
    try {
      final seed = await _secureStorage.readIdentityPrivateKey();
      if (seed == null) return; // no local identity yet — keys stay unset
      final myKeyPair = await _encryptionService.keyPairFromSeed(
        base64Decode(seed),
      );
      final chat = await _chatRepository.getChat(_chatId);
      _isGroup = chat.isGroup;

      if (!chat.isGroup) {
        _chatKey = await _encryptionService.deriveChatKey(
          myKeyPair: myKeyPair,
          peerPublicKeyBase64: chat.otherParticipant?.publicKey,
          chatId: _chatId,
        );
        return;
      }

      final keys = <String, SecretKey>{};
      final myId = _ref.read(sessionControllerProvider).user?.id;
      if (myId != null) {
        final myPublicKey = await _encryptionService.exportPublicKey(myKeyPair);
        final selfKey = await _encryptionService.deriveChatKey(
          myKeyPair: myKeyPair,
          peerPublicKeyBase64: myPublicKey,
          chatId: _chatId,
        );
        if (selfKey != null) keys[myId] = selfKey;
      }
      final names = <String, String>{};
      for (final participant in chat.participants ?? const []) {
        names[participant.id] = participant.displayName;
        final key = await _encryptionService.deriveChatKey(
          myKeyPair: myKeyPair,
          peerPublicKeyBase64: participant.publicKey,
          chatId: _chatId,
        );
        if (key != null) keys[participant.id] = key;
      }
      _groupKeys = keys;
      _participantNames = names;
    } catch (_) {
      // Best-effort — a chat that can't derive its key(s) yet still
      // loads, as undecryptable placeholders.
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final messages = await _repository.listMessages(_chatId);
      return Future.wait(messages.map(_decryptForDisplay));
    });
    if (!mounted) return;
    state = result;
    if (result.hasValue) {
      // A successful load means the thread is being viewed — mark it
      // read. Best-effort.
      unawaited(_repository.markRead(_chatId).catchError((_) {}));
    }
  }

  /// Decrypts a text message's `body` in place; leaves anything else
  /// untouched (a group media message's `body` holds a wrapped media
  /// key instead, decrypted lazily elsewhere).
  Future<Message> _decryptForDisplay(Message message) async {
    if (message.type != 'text' || message.body == null) return message;
    return message.copyWith(
      body: await _decryptBody(message.body!, message.senderId),
    );
  }

  Future<String> _decryptBody(String envelope, String? senderId) async {
    final key = keyForSender(senderId);
    if (key == null) return undecryptableBodyPlaceholder;
    try {
      if (!_isGroup) {
        return await _encryptionService.decryptText(key, envelope);
      }
      final myId = _ref.read(sessionControllerProvider).user?.id;
      if (myId == null) return undecryptableBodyPlaceholder;
      final plaintext = await _encryptionService.decryptTextForRecipient(
        envelopeMapJson: envelope,
        myUserId: myId,
        senderKey: key,
      );
      // Null means this device has no entry in the envelope (e.g. sent
      // before it joined the group) — same placeholder either way.
      return plaintext ?? undecryptableBodyPlaceholder;
    } on DecryptionFailedException {
      return undecryptableBodyPlaceholder;
    } catch (_) {
      return undecryptableBodyPlaceholder;
    }
  }

  /// Call on every composer text change. Emits `typing:true` on the
  /// empty-to-non-empty transition, and schedules `typing:false` after
  /// [_typingStopDelay] of no further changes. Clearing the field stops
  /// typing immediately.
  void onComposerChanged(String text) {
    final hasText = text.trim().isNotEmpty;
    if (!hasText) {
      _stopTyping();
      return;
    }
    if (!_iAmTyping) {
      _iAmTyping = true;
      _socketService.emitTyping(_chatId, true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(_typingStopDelay, _stopTyping);
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_iAmTyping) {
      _iAmTyping = false;
      _socketService.emitTyping(_chatId, false);
    }
  }

  Future<void> send(String body) async {
    _stopTyping(); // sending counts as "done typing"
    final tempId = 'local-${_tempIdCounter++}';
    final myId = _ref.read(sessionControllerProvider).user?.id;
    final optimistic = Message(
      id: tempId,
      chatId: _chatId,
      senderId: myId,
      type: 'text',
      body: body, // plaintext — local only until sent
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    _appendLocal(optimistic);
    await _attemptSend(tempId, body);
  }

  /// Retries a `failed` message in place (same position, same temp id).
  /// [body] is plaintext, like [send].
  Future<void> retry(String tempId, String body) async {
    _setLocalStatus(tempId, MessageStatus.sending);
    await _attemptSend(tempId, body);
  }

  Future<void> _attemptSend(String tempId, String plaintext) async {
    if (!_encryptionReady) {
      // Can't encrypt without a key — fail fast rather than send
      // unprotected.
      if (!mounted) return;
      _setLocalStatus(tempId, MessageStatus.failed);
      return;
    }
    try {
      // A group has no single shared key — one envelope per current
      // participant, including this device.
      final envelope = _isGroup
          ? await _encryptionService.encryptTextForRecipients(
              _groupKeys,
              plaintext,
            )
          : await _encryptionService.encryptText(_chatKey!, plaintext);
      final sent = await _repository.sendMessage(_chatId, envelope);
      if (!mounted) return;
      // Swap in the plaintext already on hand instead of decrypting our
      // own just-sent message.
      _resolveLocal(tempId, sent.copyWith(body: plaintext));
    } catch (_) {
      if (!mounted) return;
      _setLocalStatus(tempId, MessageStatus.failed);
    }
  }

  /// Sends a picked, already-compressed image, optimistically — same
  /// pattern as [send], carrying plaintext bytes in [Message.localBytes]
  /// until the upload resolves.
  Future<void> sendImage(Uint8List bytes) => _sendMedia(bytes, 'image');

  Future<void> sendVideo(Uint8List bytes) => _sendMedia(bytes, 'video');

  Future<void> sendAudio(Uint8List bytes) => _sendMedia(bytes, 'audio');

  Future<void> _sendMedia(Uint8List bytes, String type) async {
    final tempId = 'local-${_tempIdCounter++}';
    final myId = _ref.read(sessionControllerProvider).user?.id;
    final optimistic = Message(
      id: tempId,
      chatId: _chatId,
      senderId: myId,
      type: type,
      localBytes: bytes,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    _appendLocal(optimistic);
    await _attemptMediaSend(tempId, bytes, type);
  }

  /// Retries a `failed` media send in place, using the bytes already in
  /// [state] rather than asking the caller to re-pick.
  Future<void> retryMedia(String tempId) async {
    final bytes = _localBytesOf(tempId);
    if (bytes == null) return; // nothing sane to retry
    _setLocalStatus(tempId, MessageStatus.sending);
    await _attemptMediaSend(tempId, bytes, _typeOf(tempId));
  }

  String _typeOf(String messageId) {
    final current = state.valueOrNull ?? const [];
    for (final message in current) {
      if (message.id == messageId) return message.type;
    }
    return 'image';
  }

  Uint8List? _localBytesOf(String messageId) {
    final current = state.valueOrNull ?? const [];
    for (final message in current) {
      if (message.id == messageId) return message.localBytes;
    }
    return null;
  }

  Future<void> _attemptMediaSend(
    String tempId,
    Uint8List plaintextBytes,
    String type,
  ) async {
    if (!_encryptionReady) {
      if (!mounted) return;
      _setLocalStatus(tempId, MessageStatus.failed);
      return;
    }
    try {
      final Uint8List encryptedBytes;
      String? wrappedKey; // group-only
      if (_isGroup) {
        final result = await _encryptionService.encryptMediaForRecipients(
          _groupKeys,
          plaintextBytes,
        );
        encryptedBytes = result.encryptedBytes;
        wrappedKey = result.wrappedKeysJson;
      } else {
        encryptedBytes = await _encryptionService.encryptBytes(
          _chatKey!,
          plaintextBytes,
        );
      }
      final sent = await _repository.sendMediaMessage(
        _chatId,
        encryptedBytes,
        type,
        body: wrappedKey,
      );
      if (!mounted) return;
      _resolveLocal(tempId, sent);
    } catch (_) {
      if (!mounted) return;
      _setLocalStatus(tempId, MessageStatus.failed);
    }
  }

  /// Edits one of my own messages. Not optimistic — waits for the
  /// server, so a rejected edit just leaves the original text in place.
  /// Throws [ApiException] if this chat has no encryption key yet.
  Future<void> editMessage(String messageId, String newBody) async {
    if (!_encryptionReady) {
      throw const ApiException(
        statusCode: null,
        code: 'ENCRYPTION_NOT_READY',
        message: 'Encryption is not ready yet. Try again in a moment.',
      );
    }
    final envelope = _isGroup
        ? await _encryptionService.encryptTextForRecipients(_groupKeys, newBody)
        : await _encryptionService.encryptText(_chatKey!, newBody);
    final updated = await _repository.editMessage(_chatId, messageId, envelope);
    if (!mounted) return;
    _replaceMessage(updated.copyWith(body: newBody));
  }

  void _onEdited(Message message) {
    if (message.chatId != _chatId) return;
    unawaited(_replaceDecrypted(message));
  }

  Future<void> _replaceDecrypted(Message message) async {
    final decrypted = await _decryptForDisplay(message);
    if (!mounted) return;
    _replaceMessage(decrypted);
  }

  /// Deletes one of my own messages. Not optimistic. The backend
  /// soft-deletes (a tombstone) and returns it, replacing the message
  /// in place.
  Future<void> deleteMessage(String messageId) async {
    final tombstone = await _repository.deleteMessage(_chatId, messageId);
    if (!mounted) return;
    _replaceMessage(tombstone);
  }

  void _onDeleted(Message message) {
    if (message.chatId != _chatId) return;
    _replaceMessage(message);
  }

  /// Creates a poll in this group chat — comes back as a new message.
  /// Not optimistic, so this just appends the confirmed message once it
  /// exists (deduped against its own `message:new` echo).
  Future<void> createPoll({
    required String question,
    required List<String> options,
    required bool isAnonymous,
  }) async {
    final message = await _pollRepository.createPoll(
      _chatId,
      question: question,
      options: options,
      isAnonymous: isAnonymous,
    );
    if (!mounted) return;
    _appendIfAbsent(message);
  }

  /// Casts or changes this device's own vote. Not optimistic.
  Future<void> castVote(
    String messageId,
    String pollId,
    String optionId,
  ) async {
    final poll = await _pollRepository.vote(_chatId, pollId, optionId);
    if (!mounted) return;
    _replacePoll(messageId, poll);
  }

  /// Retracts this device's own vote.
  Future<void> retractVote(String messageId, String pollId) async {
    final poll = await _pollRepository.retractVote(_chatId, pollId);
    if (!mounted) return;
    _replacePoll(messageId, poll);
  }

  void _replacePoll(String messageId, Poll poll) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == messageId) m.copyWith(poll: poll) else m,
    ]);
  }

  // A `poll:updated` push is a live tally shared with every
  // participant — never this device's own vote — so it's merged onto
  // what's already known locally, not a full replace.
  void _onPollUpdated(PollUpdate update) {
    if (update.chatId != _chatId) return;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.poll != null && m.poll!.id == update.poll.id)
          m.copyWith(poll: m.poll!.withBroadcastTally(update.poll))
        else
          m,
    ]);
  }

  void _replaceMessage(Message message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == message.id) message else m,
    ]);
  }

  void _onIncoming(Message message) {
    if (message.chatId != _chatId) return;
    unawaited(_appendIncomingDecrypted(message));
  }

  Future<void> _appendIncomingDecrypted(Message message) async {
    if (state.valueOrNull == null) return; // history not loaded yet
    if (state.valueOrNull!.any((m) => m.id == message.id)) {
      return; // already have it
    }
    final decrypted = await _decryptForDisplay(message);
    if (!mounted) return;
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((m) => m.id == decrypted.id)) return; // re-check post-await
    state = AsyncValue.data([...current, decrypted]);
  }

  void _onStatus(MessageStatusUpdate update) {
    if (update.chatId != _chatId) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final ids = update.messageIds.toSet();
    state = AsyncValue.data([
      for (final m in current)
        if (ids.contains(m.id) && _isForwardTransition(m.status, update.status))
          m.copyWith(status: update.status)
        else
          m,
    ]);
  }

  // Guards against an out-of-order status push regressing what's
  // shown.
  bool _isForwardTransition(MessageStatus from, MessageStatus to) {
    const rank = {
      MessageStatus.sent: 0,
      MessageStatus.delivered: 1,
      MessageStatus.read: 2,
    };
    final fromRank = rank[from];
    final toRank = rank[to];
    if (fromRank == null || toRank == null) return false;
    return toRank > fromRank;
  }

  void _appendLocal(Message message) {
    final current = state.valueOrNull ?? const [];
    state = AsyncValue.data([...current, message]);
  }

  // Appends a server-confirmed message with no local placeholder to
  // swap out (see [createPoll]) — skipped if the socket's own echo
  // already landed first.
  void _appendIfAbsent(Message message) {
    final current = state.valueOrNull ?? const [];
    if (current.any((m) => m.id == message.id)) return;
    state = AsyncValue.data([...current, message]);
  }

  void _setLocalStatus(String id, MessageStatus status) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == id) m.copyWith(status: status) else m,
    ]);
  }

  // Swaps the local placeholder for the server-confirmed message in
  // place. If the confirmed message already arrived via the socket
  // first, just drops the placeholder instead of duplicating.
  void _resolveLocal(String tempId, Message serverMessage) {
    final current = state.valueOrNull;
    if (current == null) return;
    final alreadyPresent = current.any((m) => m.id == serverMessage.id);
    state = AsyncValue.data([
      for (final m in current)
        if (m.id != tempId) m else if (!alreadyPresent) serverMessage,
    ]);
  }

  @override
  void dispose() {
    _stopTyping(); // don't leave the other side hanging
    _messageSubscription.cancel();
    _statusSubscription.cancel();
    _editedSubscription.cancel();
    _deletedSubscription.cancel();
    _pollUpdatedSubscription.cancel();
    super.dispose();
  }
}

final chatDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatDetailController, AsyncValue<List<Message>>, String>((
      ref,
      chatId,
    ) {
      return ChatDetailController(
        ref,
        chatId,
        ref.watch(messageRepositoryProvider),
        ref.watch(chatRepositoryProvider),
        ref.watch(pollRepositoryProvider),
        ref.watch(encryptionServiceProvider),
      );
    });
