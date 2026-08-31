import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/services/api_client.dart';

/// Empty-list stand-in for [ChatRepository], for widget tests.
///
/// Any test that pumps the full [MessengerApp] and reaches an
/// authenticated state hits this repository via the chats controllers.
/// Without overriding it, they fall through to a real, unmocked network
/// call and land the chat list on its error state instead of empty.
/// Override `chatRepositoryProvider` with this — the chat list's own
/// content is covered by the chats feature's own tests.
class FakeChatRepository extends ChatRepository {
  FakeChatRepository() : super(ApiClient());

  @override
  Future<List<Chat>> listChats({required bool archived}) async => const [];
}
