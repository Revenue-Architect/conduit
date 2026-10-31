import 'package:conduit/features/hermes/motion/hermez_card_morph.dart';
import 'package:conduit/features/hermes/motion/hermez_card_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Steps extends StatefulWidget {
  const _Steps();

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => HermezCardMorph(
    depth: _open ? 1 : 0,
    raised: _open,
    child: _open
        ? TextButton(
            key: const ValueKey('detail'),
            onPressed: () => setState(() => _open = false),
            child: const Text('Back'),
          )
        : Align(
            key: const ValueKey('list'),
            alignment: Alignment.topCenter,
            child: TextButton(
              onPressed: () => setState(() => _open = true),
              child: const Text('Routine'),
            ),
          ),
  );
}

void main() {
  // The owner's rule, from the Morphlet reference: a step opened inside a
  // card changes in place in the same card, which reshapes to it. One card,
  // a short overlap, never a second surface or a wait.
  testWidgets('a nested step changes in place and the card reshapes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => pushHermezFullCard<void>(
                context,
                builder: (_) => const _Steps(),
              ),
              child: const Text('Scheduled'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scheduled'));
    await tester.pumpAndSettle();
    final card = find.byType(_Steps);
    final resting = tester.getSize(card).height;

    await tester.tap(find.text('Routine'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Mid-change both steps are there, in the one card.
    expect(find.text('Routine'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(card, findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Routine'), findsNothing);
    expect(tester.getSize(card).height, greaterThan(resting + 50));

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Routine'), findsOneWidget);
    expect(tester.getSize(card).height, closeTo(resting, 1));
  });
}
