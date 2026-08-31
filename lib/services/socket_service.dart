import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../config/env.dart';
import '../models/message.dart';
import '../models/message_status_update.dart';
import '../models/poll_update.dart';
import '../models/typing_update.dart';
import 'secure_storage_service.dart';

/// The app's single realtime connection. Messages are always *sent* over
/// REST (see `MessageRepository.sendMessage`) — this only carries the
/// server's push of `message:new`/`message:status` events back down, for
/// whichever chats this user is a participant in (the server decides
/// room membership at connect time; see backend/src/sockets/index.js).
/// Typing indicators are the one thing this class also *sends*, not
/// just receives — they're ephemeral and have no REST counterpart at all.
///
/// Connected once the session is authenticated and disconnected on
/// logout — see `socketServiceProvider` in core_providers.dart for that
/// wiring, mirroring how `ApiClient` attaches the access token per
/// request, except a socket authenticates once, at connect time.
class SocketService {
  SocketService({SecureStorageService? secureStorage})
    : _secureStorage = secureStorage ?? SecureStorageService();

  final SecureStorageService _secureStorage;
  socket_io.Socket? _socket;
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<MessageStatusUpdate> _statusController =
      StreamController<MessageStatusUpdate>.broadcast();
  final StreamController<TypingUpdate> _typingController =
      StreamController<TypingUpdate>.broadcast();
  final StreamController<Message> _editedMessageController =
      StreamController<Message>.broadcast();
  final StreamController<Message> _deletedMessageController =
      StreamController<Message>.broadcast();
  final StreamController<PollUpdate> _pollUpdatedController =
      StreamController<PollUpdate>.broadcast();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  bool _isConnected = false;

  /// Every `message:new` push this socket receives, for any chat the
  /// current user is in — consumers filter by chatId themselves (see
  /// `ChatDetailController` and `ActiveChatsController`).
  Stream<Message> get messageStream => _messageController.stream;

  /// Every `message:edited` push — the message's full, current shape
  /// (including `editedAt`), same filter-it-yourself contract as
  /// [messageStream].
  Stream<Message> get editedMessageStream => _editedMessageController.stream;

  /// Every `message:deleted` push — the message's tombstone shape
  /// (`body`/`mediaUrl` already null, `deletedAt` set), same
  /// filter-it-yourself contract as [messageStream].
  Stream<Message> get deletedMessageStream => _deletedMessageController.stream;

  /// Every `message:status` push (sent → delivered → read), for any
  /// chat — same filter-it-yourself contract as [messageStream].
  Stream<MessageStatusUpdate> get statusStream => _statusController.stream;

  /// Every `poll:updated` push — a poll's live tally after a vote was
  /// cast, changed, or retracted, for any chat — same filter-it-yourself
  /// contract as [messageStream]. Never carries the recipient's own vote
  /// (see [PollUpdate]'s doc comment); [ChatDetailController] merges it
  /// into what it already locally knows.
  Stream<PollUpdate> get pollUpdatedStream => _pollUpdatedController.stream;

  /// Every `typing` push from another participant — same
  /// filter-it-yourself contract as [messageStream]. The backend never
  /// echoes a typing event back to whoever sent it, so this never carries
  /// this device's own typing state.
  Stream<TypingUpdate> get typingStream => _typingController.stream;

  /// Whether the realtime connection is currently up. `false` before the
  /// first successful handshake, while offline, and while the underlying
  /// `socket.io` client is auto-reconnecting after a drop. Read this for
  /// a point-in-time check; [connectionStatusStream] is the live feed
  /// the same value comes from.
  bool get isConnected => _isConnected;

  /// Fires every time [isConnected] changes — used to show a small
  /// "no connection" banner (see `ConnectionBanner`) rather than leaving
  /// a dropped realtime connection silent. REST calls (sending a
  /// message, editing, etc.) don't depend on this socket at all, so a
  /// disconnect here doesn't block anything — it only means realtime
  /// pushes (new messages, typing, status updates) are delayed until
  /// `socket.io`'s automatic reconnection succeeds.
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  void _setConnected(bool connected) {
    if (_isConnected == connected) return;
    _isConnected = connected;
    _connectionStatusController.add(connected);
  }

  /// Parses one socket payload and adds it to [controller] — shared by
  /// every `socket.on(...)` handler below so a malformed payload for
  /// any one of them (an unexpected shape, a missing required field)
  /// can only ever drop that one event, logged and otherwise harmless,
  /// rather than throwing out of a JS-interop event callback where
  /// nothing in this app can guarantee it'd be caught as cleanly as an
  /// ordinary Dart exception would be. In practice this should be
  /// unreachable — the backend's own shape is what `fromJson` expects,
  /// by construction — but "the backend and client can never disagree"
  /// isn't a guarantee worth a crash if it's ever wrong.
  void _emit<T>(
    String event,
    dynamic data,
    StreamController<T> controller,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (data is! Map) return;
    try {
      controller.add(fromJson(Map<String, dynamic>.from(data)));
    } catch (err) {
      debugPrint('Ignoring malformed "$event" socket payload: $err');
    }
  }

  void connect(String accessToken) {
    disconnect(); // replace any existing connection (e.g. after a token refresh)

    final socket = socket_io.io(
      Env.socketUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          // A function, not a plain `{'token': accessToken}` map — that
          // would bake in whatever token was current *at this call*
          // forever, including on every automatic reconnection attempt
          // socket.io makes after a drop. If the access token has since
          // rotated (a background REST 401 silently refreshed it — see
          // ApiClient) by the time a reconnect actually happens, retrying
          // with the now-stale token this closure captured would just
          // keep failing, leaving `ConnectionBanner` stuck on
          // "reconnecting…" indefinitely even though a perfectly valid
          // token exists in storage. Re-reading it fresh on every
          // (re)connection attempt is what actually lets a dropped
          // socket recover on its own instead of needing a full logout/
          // login to fix.
          .setAuthFn((callback) async {
            final token = await _secureStorage.readAccessToken() ?? accessToken;
            callback({'token': token});
          })
          .build(),
    );

    socket.on('connect', (_) => _setConnected(true));
    // Both a graceful disconnect and a failed connection attempt mean
    // "not connected right now" from the banner's point of view — the
    // client keeps retrying either way (socket.io's default reconnection
    // behavior, left at its defaults), this just reflects that honestly
    // instead of only covering the "was connected, then dropped" case.
    socket.on('disconnect', (_) => _setConnected(false));
    socket.on('connect_error', (_) => _setConnected(false));

    socket.on(
      'message:new',
      (data) =>
          _emit('message:new', data, _messageController, Message.fromJson),
    );
    socket.on(
      'message:status',
      (data) => _emit(
        'message:status',
        data,
        _statusController,
        MessageStatusUpdate.fromJson,
      ),
    );
    socket.on(
      'typing',
      (data) => _emit('typing', data, _typingController, TypingUpdate.fromJson),
    );
    socket.on(
      'message:edited',
      (data) => _emit(
        'message:edited',
        data,
        _editedMessageController,
        Message.fromJson,
      ),
    );
    socket.on(
      'message:deleted',
      (data) => _emit(
        'message:deleted',
        data,
        _deletedMessageController,
        Message.fromJson,
      ),
    );
    socket.on(
      'poll:updated',
      (data) => _emit(
        'poll:updated',
        data,
        _pollUpdatedController,
        PollUpdate.fromJson,
      ),
    );

    socket.connect();
    _socket = socket;
  }

  /// Fire-and-forget, like the event itself — a no-op while disconnected
  /// rather than an error, since a missed typing notification is never
  /// worth surfacing to the user.
  void emitTyping(String chatId, bool isTyping) {
    _socket?.emit('typing', {'chatId': chatId, 'isTyping': isTyping});
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _setConnected(false);
  }
}
