import 'package:conduit/features/hermes/widgets/hermez_bot_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bot marks draw from cached images in both themes and sizes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Wrap(
            children: [
              for (final identity in HermezBotIdentity.values)
                for (final size in [24.0, 44.0, 88.0])
                  HermezBotMark(identity: identity, size: size, label: 'x'),
            ],
          ),
        ),
      );
      // A second frame paints the same marks again from the cache.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(HermezBotMark),
        findsNWidgets(HermezBotIdentity.values.length * 3),
      );
      expect(find.bySemanticsLabel('Bot x'), findsWidgets);
    }
  });
}
