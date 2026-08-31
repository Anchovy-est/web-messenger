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

/// How long the composer can sit idle before we tell the other side we've
/// stopped typing, if [ChatDetailController.onComposerChanged] doesn't
/// fire again first — mirrors the receiving side's own 5s safety-net
/// timeout in `TypingIndicatorController`, just shorter, since this one's
/// meant to fire during normal pauses in typing, not just after a dropped
/// event.
const _typingStopDelay = Duration(seconds: 3);

/// Backs a single chat's message thread. One instance per chat (keyed by
/// chatId via `.family`) — loads history on creation, then keeps itself
/// current by merging in `message:new` pushes for this chat from the
/// app's one socket connection (see `SocketService`), and by applying
/// `message:status` pushes as messages move sent → delivered → read.
/// Messages are always *sent* over REST; the socket only ever
/// adds to the list, and only messages not already present (by id) —
/// since sending a message also gets it appended locally from the REST
/// response, and that same message is then pushed right back down the
/// socket to every participant (sender included, since they're a
/// participant too), de-duping by id is what keeps it from appearing
/// twice.
///
/// Sending is optimistic: a local placeholder (a client-generated id,
/// status `sending`) appears immediately, then either turns into the
/// server-confirmed message (`sent`) or, on failure, `failed` — with
/// [retry] to try the same content again in place.
///
/// Also owns *sending* this chat's typing indicator — receiving the
/// other participant's is a separate, lighter-weight concern; see
/// `TypingIndicatorController`.
///
/// Also owns this chat's end-to-end encryption. Every `Message` that
/// ever enters [state] has an already-*decrypted*
/// plaintext `body` — decryption happens once, right here, the moment a
/// message is loaded/received/sent, so nothing downstream (the bubble
/// widgets, the chat list preview) needs to know encryption exists for
/// *text*. Media is different: a message's `mediaUrl` stays exactly what
/// the server returned (still pointing at ciphertext bytes on disk) —
/// decrypting a whole image/video eagerly for every message in history
/// would be wasteful, so that happens lazily, only when a bubble actually
/// renders one, via [keyForSender] (see `_ImageContent`/`_VideoContent`
/// in chat_media_content.dart).
///
/// A 1:1 chat has one shared key both participants derive independently
/// (see [_chatKey]); a group has no such single shared secret, so
/// instead each message is individually wrapped once per recipient (see
/// [_groupKeys] and `EncryptionService`'s "Group messaging" section) —
/// everything above still holds either way, just per-sender instead of
/// chat-wide for a group.
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

  /// This chat's derived AES-256-GCM key — only ever set for a 1:1 chat.
  /// `null` either because this device has no identity keypair of its
  /// own yet, the other participant hasn't registered a public key (see
  /// `EncryptionService.deriveChatKey`), or this chat is actually a
  /// group (see [_groupKeys] instead — a group has no single shared key
  /// the way a 1:1 chat does).
  SecretKey? _chatKey;

  /// This device's pairwise key with each *other* participant of a
  /// *group* chat, keyed by their user id — including this device's own
  /// user id, via a key derived against its own public key. That
  /// self-entry isn't a mistake: without it, a device could decrypt
  /// everyone else's group messages but never its own again after a
  /// reload, since [send]/[_attemptSend] wrap a message once per
  /// recipient and a device is never its own "recipient" otherwise. See
  /// `EncryptionService`'s "Group messaging" section for the full
  /// reasoning. Empty (not used at all) for a 1:1 chat.
  Map<String, SecretKey> _groupKeys = {};

  bool _isGroup = false;

  /// Whether this chat is a group — exposed so `ChatDetailScreen` (and,
  /// through it, `chat_media_content.dart`) can tell which of
  /// [_chatKey]/[_groupKeys] applies without duplicating that logic.
  bool get isGroup => _isGroup;

  /// Every *other* group participant's display name, by user id — a 1:1
  /// chat never needs this (there's only ever one other participant,
  /// already named in the app bar), but a group message bubble from
  /// someone other than the viewer needs to say *who*, since "not me"
  /// could be any of several people. Empty for a 1:1 chat.
  Map<String, String> _participantNames = {};
  Map<String, String> get participantNames => _participantNames;

  /// The key to use to decrypt something [senderId] encrypted — for a
  /// 1:1 chat that's just [_chatKey] regardless of who sent it (the key
  /// is symmetric, shared by both participants); for a group it's
  /// [senderId]'s own entry in [_groupKeys], since each participant
  /// wraps a message with a different key per recipient. Exposed so
  /// `ChatDetailScreen` can hand it to the media-rendering widgets (see
  /// `chat_media_content.dart`), which need it to decrypt image/video/
  /// audio bytes on demand, keyed by whichever message they're actually
  /// rendering rather than one chat-wide value.
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
      // Best-effort — see the class doc comment on what missing keys
      // mean for callers. A chat that can't derive its key(s) yet still
      // loads (as undecryptable placeholders); it isn't a hard failure.
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
      // Loading history successfully means the thread is actually being
      // viewed right now — mark whatever's in it as read. Best-effort:
      // this is a courtesy to the other participant, not something the
      // viewer needs to know failed.
      unawaited(_repository.markRead(_chatId).catchError((_) {}));
    }
  }

  /// Decrypts a text message's `body` in place, or leaves a non-text/
  /// already-bodyless message untouched — media messages carry no inline
  /// body to decrypt for display (a *group* media message's `body` holds
  /// a wrapped media key instead, decrypted separately and lazily, only
  /// when a bubble actually renders it — see chat_media_content.dart).
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
      // A `null` result means this device simply has no entry in the
      // envelope (e.g. a message sent before it joined the group) —
      // same undecryptable placeholder as an outright decryption
      // failure, since there's nothing more specific to show either way.
      return plaintext ?? undecryptableBodyPlaceholder;
    } on DecryptionFailedException {
      return undecryptableBodyPlaceholder;
    } catch (_) {
      return undecryptableBodyPlaceholder;
    }
  }

  /// Call on every composer text change. Emits a `typing:true` the moment
  /// the field goes from empty to non-empty (not on every keystroke —
  /// that would flood the socket for no visible benefit, since the
  /// receiving side just shows/hides one indicator either way), and
  /// schedules a `typing:false` for [_typingStopDelay] after the *last*
  /// change, restarting that timer on every subsequent change. Clearing
  /// the field stops typing immediately rather than waiting out the timer.
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
    _stopTyping(); // sending counts as "done typing", even mid-debounce
    final tempId = 'local-${_tempIdCounter++}';
    final myId = _ref.read(sessionControllerProvider).user?.id;
    final optimistic = Message(
      id: tempId,
      chatId: _chatId,
      senderId: myId,
      type: 'text',
      body: body, // plaintext — this is purely local until it's sent
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    _appendLocal(optimistic);
    await _attemptSend(tempId, body);
  }

  /// Retries a message that previously ended up `failed`, in place (same
  /// position in the list, same temp id) rather than moving it to the end
  /// — so a retry doesn't reorder the thread out of send order. [body] is
  /// plaintext, same as [send] — every `Message.body` in [state] already
  /// is (see the class doc comment), so a caller reading it straight off
  /// the failed message needs no extra decryption step.
  Future<void> retry(String tempId, String body) async {
    _setLocalStatus(tempId, MessageStatus.sending);
    await _attemptSend(tempId, body);
  }

  Future<void> _attemptSend(String tempId, String plaintext) async {
    if (!_encryptionReady) {
      // Can't encrypt without a key — failing fast (no network call) is
      // more honest than sending something we can't actually protect.
      if (!mounted) return;
      _setLocalStatus(tempId, MessageStatus.failed);
      return;
    }
    try {
      // A group has no single shared key to encrypt one envelope with —
      // instead, one envelope per current participant (this device
      // included; see `_groupKeys`'s doc comment), each recipient
      // decrypting only their own entry on the way back in.
      final envelope = _isGroup
          ? await _encryptionService.encryptTextForRecipients(
              _groupKeys,
              plaintext,
            )
          : await _encryptionService.encryptText(_chatKey!, plaintext);
      final sent = await _repository.sendMessage(_chatId, envelope);
      if (!mounted) return;
      // The server echoes back the ciphertext body it stored — swap in
      // the plaintext already on hand instead of decrypting our own
      // just-sent message right back.
      _resolveLocal(tempId, sent.copyWith(body: plaintext));
    } catch (_) {
      if (!mounted) return;
      _setLocalStatus(tempId, MessageStatus.failed);
    }
  }

  /// Sends a picked-and-already-compressed image as a new message,
  /// optimistically — same local-placeholder pattern as [send], just
  /// carrying the plaintext image bytes in [Message.localBytes] instead
  /// of text in [Message.body] until the upload resolves. The bubble
  /// renders those bytes directly via `Image.memory` while
  /// `status == sending`/`failed`; once it's `sent`, rendering switches
  /// to fetching and decrypting the server copy (see `_ImageContent` in
  /// chat_media_content.dart) — the bytes themselves are only ever
  /// encrypted in transit/at rest, never on this device. Bytes, not a
  /// local file path, is what makes this work on Web too — see
  /// `Message.localBytes`'s doc comment.
  Future<void> sendImage(Uint8List bytes) => _sendMedia(bytes, 'image');

  /// Same as [sendImage], for a picked-and-already-compressed video.
  Future<void> sendVideo(Uint8List bytes) => _sendMedia(bytes, 'video');

  /// Same as [sendImage]/[sendVideo], for a just-finished voice
  /// recording's bytes (no separate compression step; voice recordings
  /// are already small at the bitrate `AudioRecorderService` records
  /// at).
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

  /// Retries a `failed` image/video/audio send in place — mirrors
  /// [retry], just for media. The bytes are read back off the still-
  /// `failed` entry already in [state] (via [Message.localBytes]) rather
  /// than asked of the caller, since a retry re-sends the exact same
  /// already-compressed bytes, never re-picks or re-compresses — same
  /// reasoning as [_typeOf] below for `type`.
  Future<void> retryMedia(String tempId) async {
    final bytes = _localBytesOf(tempId);
    if (bytes == null) {
      // The message this refers to is gone from state, or was never a
      // local media placeholder to begin with — nothing sane to retry.
      return;
    }
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
      String? wrappedKey; // group-only — see MessageRepository.sendMediaMessage
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

  /// Edits one of *my own* messages — the backend is the real
  /// gatekeeper (see `MessageRepository.editMessage`'s doc comment), but
  /// the UI only ever offers this action on my own bubbles in the first
  /// place. Unlike [send]/[retry], this isn't optimistic: the message
  /// only changes once the server confirms it, so a rejected edit simply
  /// leaves the original text in place — the caller (the edit dialog)
  /// is expected to catch a failure and let the user try again.
  ///
  /// Throws [ApiException] (same as a rejected edit from the backend, so
  /// the edit dialog's existing error handling covers this without
  /// changes) if this chat has no encryption key yet — there's nothing
  /// safe to send in that case.
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

  /// Deletes one of *my own* messages — same reasoning as
  /// [editMessage]: not optimistic, the UI only offers this on my own
  /// messages, and a rejection is the caller's (the confirm dialog's) to
  /// surface. The backend soft-deletes (a tombstone, not a gap in the
  /// thread) and returns that tombstone, which replaces the message in
  /// place exactly like an edit does. No encryption/decryption involved —
  /// a tombstone's `body`/`mediaUrl` are already nulled server-side.
  Future<void> deleteMessage(String messageId) async {
    final tombstone = await _repository.deleteMessage(_chatId, messageId);
    if (!mounted) return;
    _replaceMessage(tombstone);
  }

  void _onDeleted(Message message) {
    if (message.chatId != _chatId) return;
    _replaceMessage(message);
  }

  /// Creates a poll in this (group) chat — comes back as a brand-new
  /// message, exactly like [send]/[sendImage] do, except not
  /// optimistic: a poll has no plaintext to show immediately the way a
  /// text message does, so this simply appends the server-confirmed
  /// message once it exists (deduping against the same message's own
  /// `message:new` echo — see [_appendIfAbsent] — the same race
  /// [_resolveLocal] guards against for other sends).
  ///
  /// Throws [ApiException] on failure (e.g. this chat isn't a group);
  /// the caller (the create-poll dialog) is expected to catch that and
  /// show it rather than have this fail silently.
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

  /// Casts (or, if [optionId] differs from whatever was already voted,
  /// changes) this device's own vote — not optimistic, so the tally
  /// shown always reflects what the server actually recorded, including
  /// [Poll.myVoteOptionId] for this same request's caller (a realtime
  /// `poll:updated` push never carries that — see [_onPollUpdated]).
  Future<void> castVote(
    String messageId,
    String pollId,
    String optionId,
  ) async {
    final poll = await _pollRepository.vote(_chatId, pollId, optionId);
    if (!mounted) return;
    _replacePoll(messageId, poll);
  }

  /// Retracts this device's own vote — same non-optimistic shape as
  /// [castVote].
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

  // A `poll:updated` push is a live tally, shared identically with every
  // participant — never this device's own vote (see [PollUpdate]'s doc
  // comment) — so it's merged onto whatever this device already knows
  // about its own vote via [Poll.withBroadcastTally], never replacing
  // the poll outright the way [_replacePoll] does for this device's own
  // vote/retract actions.
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
    // Still loading, or failed to load, initial history — nothing to
    // append to yet.
    if (state.valueOrNull == null) return;
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

  // Guards against an out-of-order status push regressing what's shown —
  // e.g. a slow "delivered" event arriving after a faster "read" one
  // already landed.
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

  // Appends a server-confirmed message that was never optimistically
  // shown (there's no local placeholder/tempId to swap out — see
  // [createPoll]) — skipped if it's already present, since the socket's
  // own `message:new` echo of this same message can easily race ahead of
  // this call and land first.
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
  // place, preserving its position in the thread. If the server-confirmed
  // message already arrived separately (a race with the socket's own
  // echo of it — see the class doc comment), this just drops the
  // placeholder instead of adding a duplicate.
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
    _stopTyping(); // leaving the chat — don't leave the other side hanging
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
