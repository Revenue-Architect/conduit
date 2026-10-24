import 'package:conduit/core/models/chat_message.dart';
import 'package:conduit/features/hermes/models/hermes_subagent.dart';
import 'package:conduit/features/hermes/widgets/hermes_inline_delegation.dart';
import 'package:conduit/features/hermes/widgets/hermes_turn_delegation.dart';
import 'package:conduit/features/hermes/widgets/hermez_segments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23);
  final workers = [
    for (final name in ['Kai', 'Ops'])
      HermesSubagentState(
        id: name,
        name: name,
        goal: 'Review the actual task',
        status: HermesSubagentStatus.completed,
        startedAt: now,
        updatedAt: now,
        summary: 'Actual recorded result',
        kind: HermesDelegationKind.specialist,
        childProfile: name.toLowerCase(),
        childSessionId: 'real-$name',
        lines: const [(text: 'Read File', tool: true, error: false)],
      ),
  ];
  Widget app({
    Future<List<ChatMessage>> Function(HermesSubagentState)? load,
    TextScaler scaler = TextScaler.noScaling,
  }) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: true, textScaler: scaler),
          child: PageStorage(
            bucket: PageStorageBucket(),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  HermesInlineDelegation(
                    workers: workers,
                    parentSessionId: 'parent',
                    parentLabel: 'Chief',
                    turnKey: 'message-a',
                    loadConversation: load,
                  ),
                  const SizedBox(
                    key: ValueKey('footer'),
                    height: 50,
                    child: Text('Parent composer remains'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'expansion changes physical layout and workers remain independent',
    (tester) async {
      await tester.pumpWidget(app());
      final before = tester.getTopLeft(find.byKey(const ValueKey('footer'))).dy;
      await tester.tap(find.byKey(const ValueKey('delegation-group')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('footer'))).dy,
        greaterThan(before),
      );
      await tester.tap(find.textContaining('Kai').first);
      await tester.pumpAndSettle();
      expect(find.byType(HermezSegments), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Ops').first);
      await tester.tap(find.textContaining('Ops').first);
      await tester.pumpAndSettle();
      expect(find.byType(HermezSegments), findsNWidgets(2));
      await tester.ensureVisible(
        find.byKey(const ValueKey('delegation-group')),
      );
      await tester.tap(find.byKey(const ValueKey('delegation-group')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('footer'))).dy,
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Conversation reads supplied real messages without inventing a reply',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        app(
          load: (worker) async {
            reads++;
            return [
              ChatMessage(
                id: 'instruction',
                role: 'user',
                content: 'Actual delegated instruction',
                timestamp: now,
              ),
              ChatMessage(
                id: 'answer',
                role: 'assistant',
                content: 'Actual child answer',
                timestamp: now,
              ),
            ];
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('delegation-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Kai').first);
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.tap(find.text('Conversation').first);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.text('Actual child answer'), findsOneWidget);
      expect(find.text('Actual delegated instruction'), findsOneWidget);
      expect(find.text('Parent composer remains'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('worker origin matches exact ids and never similarly named text', () {
    final worker = HermesSubagentState(
      id: 'native',
      goal: 'Same title',
      status: HermesSubagentStatus.running,
      startedAt: now,
      updatedAt: now,
      sourceToolCallId: 'call-a',
      parentTurnId: 'turn-a',
    );
    expect(
      hermesWorkerBelongsToMessage(
        worker,
        ChatMessage(
          id: 'm',
          role: 'assistant',
          content: 'Same title',
          timestamp: now,
        ),
      ),
      isFalse,
    );
    expect(
      hermesWorkerBelongsToMessage(
        worker,
        ChatMessage(
          id: 'm',
          role: 'assistant',
          content: '',
          timestamp: now,
          metadata: {
            'hermesToolCallIds': ['call-a'],
          },
        ),
      ),
      isTrue,
    );
  });
}
