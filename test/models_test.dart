import 'package:flutter_test/flutter_test.dart';
import 'package:personal_chat_call_app/src/models.dart';

void main() {
  test('parses nested sender ids and detects current user messages', () {
    final user = AppUser.fromJson({
      '_id': 'user-1',
      'name': 'Sender',
      'email': 'sender@example.com',
    });
    final message = ChatMessage.fromJson({
      '_id': 'message-1',
      'chat': {'_id': 'chat-1'},
      'sender': {'_id': 'user-1'},
      'type': 'TEXT',
      'text': 'Hello',
      'createdAt': '2026-07-19T03:00:00.000Z',
    });

    expect(message.senderId, 'user-1');
    expect(message.isFromUser(user), isTrue);
  });
}
