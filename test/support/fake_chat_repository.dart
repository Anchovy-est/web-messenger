import 'package:mobile_messenger/features/chats/data/chat_repository.dart';
import 'package:mobile_messenger/models/chat.dart';
import 'package:mobile_messenger/services/api_client.dart';

/// Empty-list stand-in for [ChatRepository], for widget tests.
///
/// [ChatListScreen] is the app's real home screen, so any test that
/// pumps the full [MessengerApp] and reaches an authenticated
/// state will hit this repository via `activeChatsControllerProvider` /
/// `archivedChatsControllerProvider`. Without overriding it, those
/// controllers fall through to the real repository's network call, which
/// is unmocked here and lands the chat list on its error state instead of
/// the empty one these tests expect. Override `chatRepositoryProvider`
/// with this in any such test — the chat list's own content (tiles,
/// archiving, navigation) is covered by the chats feature's own tests.
class FakeChatRepository extends ChatRepository {
  FakeChatRepository() : super(ApiClient());

  @override
  Future<List<Chat>> listChats({required bool archived}) async => const [];
}
