import 'package:conduit/features/hermes/motion/hermez_card_morph.dart';
import 'package:conduit/features/hermes/motion/hermez_card_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
            child: SizedBox(
              height: 56,
              child: TextButton(
                onPressed: () => setState(() => _open = true),
                child: const Text('Routine'),
              ),
            ),
          ),
  );
}

void main() {
  // The owner's rule: a step opened inside a card is the pressed row
  // growing into the same card, which reshapes to it, never a fade.
  testWidgets('a nested step grows from its row and reshapes the card', (
    tester,
  ) async {
    HermezPressOrigin.install();
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
    final row = tester.getRect(find.text('Routine'));

    await tester.tap(find.text('Routine'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    // Early on, the step is still about the size of the row it came from.
    final clip = tester.renderObject<RenderClipRRect>(
      find.descendant(of: card, matching: find.byType(ClipRRect)).first,
    );
    final early = clip.clipper!.getClip(clip.size).outerRect;
    expect(early.height, lessThan(resting / 2));
    expect(
      (tester.getTopLeft(card) + early.center).dy,
      closeTo(row.center.dy, resting / 3),
    );

    await tester.pumpAndSettle();
    expect(find.text('Routine'), findsNothing);
    expect(tester.getSize(card).height, greaterThan(resting + 50));

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Routine'), findsOneWidget);
    expect(tester.getSize(card).height, closeTo(resting, 1));
  });
}
