/// Shown in place of message content that can't be decrypted — either
/// this chat's end-to-end encryption key hasn't finished
/// deriving yet, or the sender's/our own identity key has changed since
/// the message was sent (see docs/ENCRYPTION.md for why that's an
/// accepted trade-off, not a bug). A single shared constant so the chat
/// list preview (`ChatListController`) and an open thread
/// (`ChatDetailController`) show the exact same wording for the same
/// underlying situation, rather than each inventing their own text.
const undecryptableBodyPlaceholder = '🔒 Unable to decrypt this message';
