import 'package:conduit/features/hermes/views/hermes_chats_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: one search covers the team and Open WebUI chats alike.
  test('a search matches bot rows and Open WebUI chats', () {
    const query = 'recipe';
    final bot = ['chief', 'Chief', 'Scaling the recipe for Saturday', null];
    final openWebUi = ['Scaling a bread recipe', 'Llama 3.3 70B'];
    final other = ['Winter tires in Ontario', 'Llama 3.3 70B'];
    expect(hermesChatsMatches(query, bot), isTrue);
    expect(hermesChatsMatches(query, openWebUi), isTrue);
    expect(hermesChatsMatches(query, other), isFalse);
    expect(hermesChatsMatches('', other), isTrue);
  });
}
