import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../config/env.dart';
import '../models/message.dart';
import '../models/message_status_update.dart';
import '../models/poll_update.dart';
import '../models/typing_update.dart';
import 'secure_storage_service.dart';

/// The app's single realtime connection. Messages are always sent over
/// REST — this only carries the server's pushes back down. Typing is
/// the one thing this class also sends.
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

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Message> get editedMessageStream => _editedMessageController.stream;
  Stream<Message> get deletedMessageStream => _deletedMessageController.stream;
  Stream<MessageStatusUpdate> get statusStream => _statusController.stream;

  /// A poll's live tally after a vote is cast, changed, or retracted.
  /// Never carries the viewer's own vote — see [PollUpdate].
  Stream<PollUpdate> get pollUpdatedStream => _pollUpdatedController.stream;

  Stream<TypingUpdate> get typingStream => _typingController.stream;

  /// Whether the realtime connection is currently up.
  bool get isConnected => _isConnected;

  /// Fires whenever [isConnected] changes — drives `ConnectionBanner`.
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  void _setConnected(bool connected) {
    if (_isConnected == connected) return;
    _isConnected = connected;
    _connectionStatusController.add(connected);
  }

  /// Parses one socket payload and adds it to [controller] — a
  /// malformed payload just gets logged and dropped, never crashes.
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
    disconnect(); // replace any existing connection

    final socket = socket_io.io(
      Env.socketUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          // Re-reads the token on every (re)connect attempt, not just
          // this call, so a reconnect after a token refresh still works.
          .setAuthFn((callback) async {
            final token = await _secureStorage.readAccessToken() ?? accessToken;
            callback({'token': token});
          })
          .build(),
    );

    socket.on('connect', (_) => _setConnected(true));
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

  /// Fire-and-forget — a no-op while disconnected.
  void emitTyping(String chatId, bool isTyping) {
    _socket?.emit('typing', {'chatId': chatId, 'isTyping': isTyping});
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _setConnected(false);
  }
}
