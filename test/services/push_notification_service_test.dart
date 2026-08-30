import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/services/push_notification_service.dart';

void main() {
  group('chatIdFromNotificationData', () {
    test('returns the chatId for a message notification', () {
      final chatId = chatIdFromNotificationData({
        'type': 'message',
        'chatId': 'chat-123',
      });
      expect(chatId, 'chat-123');
    });

    test(
      'returns null for an invitation notification (nothing chat-specific to open)',
      () {
        final chatId = chatIdFromNotificationData({'type': 'invitation'});
        expect(chatId, null);
      },
    );

    test('returns null for an unrecognized or missing type', () {
      expect(chatIdFromNotificationData({}), null);
      expect(chatIdFromNotificationData({'type': 'something-else'}), null);
    });

    test(
      'returns null for a message notification with no chatId (malformed payload)',
      () {
        final chatId = chatIdFromNotificationData({'type': 'message'});
        expect(chatId, null);
      },
    );
  });
}
