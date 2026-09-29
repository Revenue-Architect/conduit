import 'package:conduit/features/hermes/services/hermes_clarify_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a single-question request is not a batch', () {
    final payload = {
      'question': 'Which?',
      'choices': ['a', 'b'],
    };
    expect(hermesClarifyBatch(payload), isNull);
    expect(hermesClarifyPrompt(payload), 'Which?');
    expect(hermesClarifyChoices(payload), ['a', 'b']);
  });

  test('a one-question batch reads like a single question', () {
    final payload = {
      'request_id': 'r',
      'questions': [
        {
          'qid': 'q0',
          'question': 'Which color?',
          'choices': ['red', 'blue'],
        },
      ],
    };
    expect(hermesClarifyBatch(payload)!.single.qid, 'q0');
    expect(hermesClarifyPrompt(payload), 'Which color?');
    expect(hermesClarifyChoices(payload), ['red', 'blue']);
    expect(hermesClarifyBatchAnswers(['q0'], 'blue'), {'q0': 'blue'});
  });

  test('several questions: numbered prompt, one line per answer', () {
    final payload = {
      'questions': [
        {'qid': 'q0', 'question': 'Drink?'},
        {'qid': 'q1', 'question': 'Time?'},
      ],
    };
    expect(hermesClarifyPrompt(payload), contains('1. Drink?'));
    expect(hermesClarifyPrompt(payload), contains('2. Time?'));
    expect(hermesClarifyChoices(payload), isEmpty);
    expect(hermesClarifyBatchAnswers(['q0', 'q1'], 'Tea\nNight'), {
      'q0': 'Tea',
      'q1': 'Night',
    });
    // A single line cannot be split: it answers the first question.
    expect(hermesClarifyBatchAnswers(['q0', 'q1'], 'Tea'), {
      'q0': 'Tea',
      'q1': '',
    });
  });
}
