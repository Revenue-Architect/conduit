import 'package:conduit/features/hermes/views/hermes_page_chrome.dart';
import 'package:conduit/features/hermes/widgets/hermez_technical_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 412.0]) {
      testWidgets('atmospheric panel stays decorative at $width $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: HermesPanel(
                backgroundVariant: HermezBackgroundVariant.editorial,
                onTap: () => taps++,
                child: const Text('Real Hermes content'),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Real Hermes content'));
        expect(taps, 1);
      });
    }
  }
}
