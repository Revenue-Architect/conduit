import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/spaces/models/spaces_models.dart';
import 'package:conduit/features/spaces/services/page_chat_launcher.dart';
import 'package:conduit/features/spaces/widgets/page_chat_picker_sheet.dart';
import 'package:flutter/material.dart';
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

  testWidgets('the picker opens, lists every profile, and returns the pick', (
    tester,
  ) async {
    HermesBot? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showPageChatPicker(
                    context,
                    pageTitle: 'Launch notes',
                    bots: ['strong', 'kai', 'default'].map(_bot).toList(),
                    chats: [_chat('kai')],
                  );
                },
                child: const Text('Ask'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    // A list inside the sheet's own scroll view used to throw here.
    expect(tester.takeException(), isNull);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('NEW'), findsNWidgets(2));
    await tester.tap(find.text('strong'));
    await tester.pumpAndSettle();
    expect(picked?.name, 'strong');
  });
}
