// Realtime layer: message delivery, status updates, typing
// indicators. Persistence and authorization still go through the
// REST layer (message.controller.js) — this file just authenticates
// the socket, joins it to a room per chat, and lets REST broadcast
// into those rooms after it persists something.
//
// Typing indicators are the exception — never persisted, so there's
// no REST counterpart; this file both receives and broadcasts them.
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

  // Auth and room-joining both happen here in `io.use`, not in the
  // `connection` handler, so room membership is in place before the
  // client can emit anything — a typing event sent right on connect
  // would otherwise race the room join and get dropped.
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
      // Every chat this user is in, archived or not, so messages
      // arrive in real time no matter which screen they're on.
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

    // Ephemeral, fire-and-forget — relayed to the rest of the room
    // (never back to the sender) and never stored. Authorization
    // reuses the room join from auth middleware: a stray event for a
    // chat this socket never joined is silently dropped.
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
