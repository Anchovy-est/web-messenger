// Realtime layer entry point: message delivery, status updates, and
// typing indicators. Persistence and authorization for messages still go
// through the REST layer (message.controller.js) — this file's job is
// just: authenticate the socket, put it in a room per chat it belongs
// to, and let the REST layer broadcast into those rooms after it
// persists something. Keeping "write" on REST and "push" on sockets
// avoids duplicating validation/auth logic in two protocols.
//
// Typing indicators are the one exception — by design they're never
// persisted, so there's no REST counterpart at all; this file both
// receives and broadcasts them directly.
const { Server } = require('socket.io');
const { verifyAccessToken } = require('../utils/jwt');
const chatModel = require('../models/chat.model');

function chatRoom(chatId) {
  return `chat:${chatId}`;
}

function attachSocketServer(httpServer) {
  const io = new Server(httpServer, {
    cors: { origin: '*' },
  });

  // Authenticates (mirrors `authenticate.js`'s REST middleware — same
  // token, same verification, just read from the handshake instead of a
  // header) *and* joins every chat room this user belongs to, both here
  // in `io.use` rather than the `connection` handler below. That matters:
  // middleware fully resolves before the client ever sees its own
  // `connect` event, so by the time client code can possibly emit
  // anything, room membership is already in place server-side. Doing the
  // room join after `connection` instead (as an `async` step in that
  // handler) leaves a window where a client that emits immediately on
  // connect — exactly what a typing indicator does — races the join and
  // gets silently dropped, since nothing’s listening/authorized yet.
  io.use(async (socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) {
      return next(new Error('UNAUTHENTICATED'));
    }
    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch {
      return next(new Error('UNAUTHENTICATED'));
    }
    socket.userId = payload.sub;

    try {
      // Every chat this user is currently in (archived or not) so a
      // message lands in real time regardless of which screen — chat
      // list or a specific chat — they're on. Not scoped to "chats the
      // client has explicitly opened": that would miss messages arriving
      // for chats the user hasn't navigated to yet in this session.
      const chatIds = await chatModel.listChatIdsForUser(socket.userId);
      for (const chatId of chatIds) {
        socket.join(chatRoom(chatId));
      }
    } catch (err) {
      console.error('Failed to join chat rooms during socket auth', err);
    }

    next();
  });

  io.on('connection', (socket) => {
    console.log(`Socket connected: ${socket.id} (user ${socket.userId})`);

    // Ephemeral, fire-and-forget: relayed to the rest of the chat's room
    // (never back to the sender — `socket.to`, not `io.to`) and never
    // written anywhere. Authorization reuses the room join from the auth
    // middleware above instead of a DB round trip: a socket is only ever
    // in `chatRoom(chatId)` if it belongs to a participant, so a stray
    // event for a chat this socket never joined is silently dropped.
    socket.on('typing', (payload) => {
      const chatId = payload?.chatId;
      const isTyping = payload?.isTyping === true;
      if (typeof chatId !== 'string' || !socket.rooms.has(chatRoom(chatId))) {
        return;
      }
      socket.to(chatRoom(chatId)).emit('typing', {
        chatId,
        userId: socket.userId,
        isTyping,
      });
    });

    socket.on('disconnect', (reason) => {
      console.log(`Socket disconnected: ${socket.id} (${reason})`);
    });
  });

  return io;
}

module.exports = { attachSocketServer, chatRoom };
