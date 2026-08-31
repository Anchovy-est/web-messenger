import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_providers.dart';
import 'chat_repository.dart';
import 'message_repository.dart';
import 'poll_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(apiClientProvider));
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(apiClientProvider));
});

final pollRepositoryProvider = Provider<PollRepository>((ref) {
  return PollRepository(ref.watch(apiClientProvider));
});
