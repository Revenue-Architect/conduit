import 'package:conduit/features/hermes/widgets/hermez_action_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    List<HermezPillAction> actions,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: HermezActionPills(actions: actions),
        ),
      ),
    ),
  );

  testWidgets('a field pill grows into a field, sends, and folds back', (
    tester,
  ) async {
    final sent = <String>[];
    var accept = false;
    await mount(tester, [
      HermezPillAction(
        label: 'Comment',
        icon: Icons.mode_comment_outlined,
        hint: 'Your note',
        onSubmit: (text) async {
          sent.add(text);
          return accept;
        },
      ),
      HermezPillAction(label: 'Stop', icon: Icons.stop, onTap: () {}),
    ]);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Comment'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    // Empty: the control closes rather than sends.
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Use the EU prices');
    await tester.pump();
    await tester.tap(find.byTooltip('Send to Hermes'));
    await tester.pumpAndSettle();
    // Refused: the field and its text stay.
    expect(sent, ['Use the EU prices']);
    expect(find.byType(TextField), findsOneWidget);
    accept = true;
    await tester.tap(find.byTooltip('Send to Hermes'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Comment'), findsOneWidget);
  });

  testWidgets('an empty field can send its own meaning from the keyboard', (
    tester,
  ) async {
    final sent = <String>[];
    await mount(tester, [
      HermezPillAction(
        label: 'Replan',
        icon: Icons.alt_route_rounded,
        emptyText: 'start again from where you are.',
        onSubmit: (text) async {
          sent.add(text);
          return true;
        },
      ),
    ]);
    await tester.tap(find.text('Replan'));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(sent, ['start again from where you are.']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Back folds an open field before leaving', (tester) async {
    await mount(tester, [
      HermezPillAction(
        label: 'Steer',
        icon: Icons.edit_outlined,
        onSubmit: (_) async => true,
      ),
    ]);
    await tester.tap(find.text('Steer'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byType(TextField), findsNothing);
  });
}
