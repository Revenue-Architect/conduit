import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/spaces/models/spaces_models.dart';
import 'package:conduit/features/spaces/services/page_chat_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

HermesBot _bot(String name) => HermesBot(name: name, title: name);

PageChatBinding _chat(String profile) => PageChatBinding(
  pageId: '00000000-0000-4000-8000-000000000001',
  profile: profile,
  sessionId: 'session-$profile',
);

void main() {
  test('profiles with a conversation for the Page come first, then kai, '
      'then the rest by name', () {
    final bots = [
      'strong',
      'default',
      'kai',
      'fast',
      'local',
    ].map(_bot).toList();
    final ordered = orderPageChatBots(bots, [_chat('local'), _chat('fast')]);
    expect(ordered.map((b) => b.name), [
      'local',
      'fast',
      'kai',
      'default',
      'strong',
    ]);
  });

  test('with no conversations kai leads', () {
    final ordered = orderPageChatBots(
      ['strong', 'kai', 'default'].map(_bot).toList(),
      const [],
    );
    expect(ordered.first.name, 'kai');
  });
}
