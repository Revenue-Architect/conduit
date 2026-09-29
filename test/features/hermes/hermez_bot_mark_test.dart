import 'dart:io';

import 'package:conduit/features/hermes/widgets/hermez_bot_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every bot identity has artwork in assets/icons', () {
    for (final identity in HermezBotIdentity.values) {
      final asset = hermezBotMarkAssets[identity];
      expect(asset, isNotNull, reason: '$identity');
      expect(File(asset!).existsSync(), isTrue, reason: asset);
    }
  });

  testWidgets('bot marks keep their square size and label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final identity in HermezBotIdentity.values)
              for (final size in [24.0, 44.0, 88.0])
                HermezBotMark(identity: identity, size: size, label: 'x'),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final marks = find.byType(HermezBotMark);
    expect(marks, findsNWidgets(HermezBotIdentity.values.length * 3));
    for (final element in marks.evaluate()) {
      final mark = element.widget as HermezBotMark;
      expect(tester.getSize(find.byWidget(mark)), Size.square(mark.size));
    }
    expect(find.bySemanticsLabel('Bot x'), findsWidgets);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.fit, BoxFit.contain);
  });
}
