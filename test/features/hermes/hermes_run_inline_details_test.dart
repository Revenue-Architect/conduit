import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/features/hermes/services/hermes_activity_presenter.dart';
import 'package:conduit/features/hermes/services/hermes_message_mapper.dart';
import 'package:conduit/features/hermes/services/hermes_run_transport.dart'
    show kHermesProviderWaitAction;
import 'package:conduit/features/hermes/widgets/hermes_run_activity_orb.dart';
import 'package:flutter_test/flutter_test.dart';

ChatStatusUpdate _wait(String text, {bool done = false}) => ChatStatusUpdate(
  action: kHermesProviderWaitAction,
  description: text,
  done: done,
  hidden: true,
);

void main() {
  group('provider wait', () {
    test('an open notice reads as a slow model, by name', () {
      expect(
        hermesProviderWaitLabel([
          _wait(
            '⏳ waiting on gpt-6-luna — provider stream open; 245s without '
            'substantive model progress',
          ),
        ]),
        'gpt-6-luna is slow to reply',
      );
    });

    test('near its watchdog it says a retry is coming', () {
      expect(
        hermesProviderWaitLabel([
          _wait(
            '⏳ still waiting on gpt-6-luna — provider stream open; 290s '
            'without substantive model progress (auto-reconnect: first '
            'progress watchdog in 10s)',
          ),
        ]),
        'gpt-6-luna is slow to reply · retrying soon',
      );
    });

    test('a cleared notice says nothing', () {
      expect(hermesProviderWaitLabel([_wait('', done: true)]), isNull);
      expect(hermesProviderWaitLabel(const []), isNull);
    });
  });

  group('turn', () {
    ChatMessage m(String id, String role, [String content = '']) => ChatMessage(
      id: id,
      role: role,
      content: content,
      timestamp: DateTime.utc(2026, 10, 24),
    );
    // The real shape of a delegated run: tool row, words, Hermes' hidden
    // wake-up, more tool rows, the result, then the owner's next prompt.
    final all = [
      m('u1', 'user', 'Show me a demo'),
      m('a1', 'assistant'),
      m('a2', 'assistant', 'I delegated it.'),
      m('n1', 'user', '[ASYNC DELEGATION BATCH COMPLETE — deleg_1]'),
      m('a3', 'assistant'),
      m('a4', 'assistant', 'Here it is.'),
      m('u2', 'user', 'Thanks'),
      m('a5', 'assistant', 'Any time.'),
    ];

    test('spans the async wake-up as one answer', () {
      final span = hermesTurnSpanKey(all, 'a1');
      expect(span.ids, ['a1', 'a2', 'a3', 'a4']);
      expect(span.leadsElsewhere, isFalse);
      expect(span.latest, isFalse);
    });

    test('a later piece of the answer defers to the line above', () {
      expect(hermesTurnSpanKey(all, 'a3').leadsElsewhere, isTrue);
      expect(hermesTurnSpanKey(all, 'a2').leadsElsewhere, isFalse);
    });

    test('the last turn is the current one', () {
      final span = hermesTurnSpanKey(all, 'a5');
      expect(span.ids, ['a5']);
      expect(span.latest, isTrue);
    });

    test('equal spans compare equal, so selection does not rebuild', () {
      expect(hermesTurnSpanKey(all, 'a1'), hermesTurnSpanKey(all, 'a2'));
    });
  });

  group('thinking', () {
    test('every message\'s thinking becomes plain lines, once', () {
      expect(
        hermesThoughtLines(const [
          ChatStatusUpdate(
            action: 'reasoning',
            description: 'Thinking… **Preparing delegation demo**',
          ),
          ChatStatusUpdate(
            action: 'reasoning',
            description:
                'Thinking… **Preparing delegation demo**\n'
                '**Preparing delegation request**',
          ),
        ]),
        ['Preparing delegation demo', 'Preparing delegation request'],
      );
      expect(
        hermesThoughtLines(const [
          ChatStatusUpdate(
            action: 'reasoning',
            description:
                'Thinking… **Loading browser guidance****Preparing live view**',
          ),
        ]),
        ['Loading browser guidance', 'Preparing live view'],
      );
      expect(hermesThoughtLines(const []), isEmpty);
    });

    test('a saved answer keeps its thinking after a reload', () {
      final messages = hermesMessagesToChatMessages([
        {'role': 'user', 'content': 'Hi'},
        {
          'id': 'a1',
          'role': 'assistant',
          'content': 'Hello!',
          'reasoning': '**Validating card layout**',
        },
      ], sessionId: 'session-1');
      final answer = messages.last;
      expect(hermesThoughtLines(answer.statusHistory), [
        'Validating card layout',
      ]);
      expect(answer.statusHistory.single.done, isTrue);
    });

    test('thinking alone does not invent an empty answer', () {
      final messages = hermesMessagesToChatMessages([
        {'role': 'assistant', 'content': '', 'reasoning': '**Planning**'},
      ], sessionId: 'session-1');
      expect(messages, isEmpty);
    });
  });
  test('a step names its verb and object once, without the plan restated', () {
    HermesActivityRow row(String verb, HermesActivityFamily family) =>
        HermesActivityRow(
          key: verb,
          verb: verb,
          state: HermesActivityRowState.done,
          family: family,
          at: DateTime.utc(2026, 10, 24),
          object: 'updating 3 task(s)',
          toolName: 'todo',
        );

    expect(
      hermesRunSteps([
        row('Updated plan', HermesActivityFamily.plan),
      ], const []).single.text,
      'Updated plan',
    );
    expect(
      hermesRunSteps([
        row('Ran command', HermesActivityFamily.command),
      ], const []).single.text,
      'Ran command · updating 3 task(s)',
    );
  });
}
