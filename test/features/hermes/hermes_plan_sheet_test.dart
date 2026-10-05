import 'package:conduit/features/chat/providers/chat_providers.dart';
import 'package:conduit/features/hermes/models/hermes_todo.dart';
import 'package:conduit/features/hermes/providers/hermes_agentic_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_agentic_state.dart';
import 'package:conduit/features/hermes/sheets/hermes_plan_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('direction drafted from an open field closes the plan sheet', (
    tester,
  ) async {
    final plan = HermesTodoSnapshot.fromJson({
      'revision': 1,
      'todos': [
        {'id': 'a', 'content': 'Check the date', 'status': 'completed'},
        {'id': 'b', 'content': 'Reply briefly', 'status': 'pending'},
      ],
    })!;
    // No live run: direction waits in the composer for the user to send.
    final container = ProviderContainer(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesAgenticStateProvider('s1').overrideWith(
          (ref) => Stream.value(HermesAgenticSnapshot(todo: plan)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showHermesPlanSheet(context, sessionId: 's1'),
                  child: const Text('Open plan'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open plan'));
    await tester.pumpAndSettle();
    expect(find.text('Reply briefly'), findsOneWidget);

    await tester.tap(find.text('Replan'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    // An empty field sends its own meaning; the field is still open when
    // the sheet hands the user over to the composer.
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(
      container.read(composerTextInsertionProvider)?.text,
      'Please revise the plan: start again from where you are.',
    );
    expect(find.text('Reply briefly'), findsNothing);
    expect(find.text('Open plan'), findsOneWidget);
  });
}
