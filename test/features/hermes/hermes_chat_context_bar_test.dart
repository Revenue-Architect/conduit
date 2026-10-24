import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/features/hermes/widgets/hermes_chat_context_bar.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String content) => ChatMessage(
  id: content,
  role: 'user',
  content: content,
  timestamp: DateTime.utc(2026, 10, 24),
);

ChatMessage _assistant(String id, {bool todo = false}) => ChatMessage(
  id: id,
  role: 'assistant',
  content: '',
  timestamp: DateTime.utc(2026, 10, 24),
  statusHistory: [
    if (todo)
      const ChatStatusUpdate(action: 'hermes_tool_todo', description: 'todo'),
  ],
);

void main() {
  test('the plan pill belongs to the turn that used the plan', () {
    final planTurn = [
      _user('make a plan'),
      _assistant('a1', todo: true),
      _user('[ASYNC DELEGATION scout] PONG'),
      _assistant('a2'),
    ];

    // Through a delegation wake-up, it is still the plan's turn.
    expect(hermesLatestTurnUsedPlan(planTurn), isTrue);
    // A later, unrelated turn does not keep a finished plan in view.
    expect(
      hermesLatestTurnUsedPlan([...planTurn, _user('hi'), _assistant('a3')]),
      isFalse,
    );
  });
}
