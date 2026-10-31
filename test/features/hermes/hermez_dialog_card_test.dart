import 'package:conduit/features/hermes/motion/hermez_card_route.dart';
import 'package:conduit/shared/widgets/themed_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _pump(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(
        body: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return context;
}

void main() {
  // The rule (pattern B): a dialog-built form is the one card's own content,
  // never an AlertDialog drawn inside a card, and it returns what was typed.
  testWidgets('a form opens as the card and returns its value', (tester) async {
    final context = await _pump(tester);
    String? saved;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    ThemedDialogs.showCustom<String>(
      context: context,
      builder: (dialogContext) => ThemedDialogs.buildBase(
        context: dialogContext,
        title: 'Rename file',
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((value) => saved = value);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      hermezCardOriginOf(tester.element(find.text('Rename file'))),
      isNull, // no control was pressed: it rises from the bottom edge
    );
    expect(
      find.ancestor(
        of: find.text('Rename file'),
        matching: find.byType(HermezCardScope),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'plan.md');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'plan.md');
  });

  // The rule (pattern A): a question that must be answered can't be
  // dismissed by the scrim; only its answers close it.
  testWidgets('a must-answer card ignores the scrim', (tester) async {
    final context = await _pump(tester);
    bool? answer;
    ThemedDialogs.confirm(
      context,
      title: 'Unpair this phone?',
      message: 'Push alerts stop until you pair again.',
      confirmText: 'Unpair',
      barrierDismissible: false,
    ).then((value) => answer = value);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Unpair this phone?'), findsOneWidget);
    expect(answer, isNull);

    await tester.tap(find.text('Unpair'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    expect(find.text('Unpair this phone?'), findsNothing);
  });
}
