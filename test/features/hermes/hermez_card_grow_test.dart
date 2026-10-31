import 'package:conduit/features/hermes/motion/hermez_card_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule (m11): a card that opens a screen grows into it, edge to edge,
  // before the screen takes its place; if the screen can't open, it is a
  // card again.
  testWidgets('a card grows to fill the screen and back', (tester) async {
    late BuildContext app;
    late BuildContext inCard;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            app = context;
            return const Scaffold();
          },
        ),
      ),
    );
    pushHermezCard<void>(
      app,
      builder: (context) {
        inCard = context;
        return const SizedBox(height: 200, child: Text('Choose a bot'));
      },
    );
    await tester.pumpAndSettle();
    Size card() => tester.getSize(find.byType(SizedBox).last);
    final resting = tester.getRect(
      find
          .ancestor(
            of: find.text('Choose a bot'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(resting.height, lessThan(400));

    final grown = growHermezCardToScreen(inCard);
    await tester.pumpAndSettle();
    await grown;
    final full = tester.getRect(
      find
          .ancestor(
            of: find.text('Choose a bot'),
            matching: find.byType(Material),
          )
          .first,
    );
    final screen = MediaQuery.sizeOf(app);
    expect(full.size, screen);

    final shrunk = shrinkHermezCardToCard(inCard);
    await tester.pumpAndSettle();
    await shrunk;
    expect(card().height, 200);
    final back = tester.getRect(
      find
          .ancestor(
            of: find.text('Choose a bot'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(back.height, resting.height);
  });
}
