import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/features/hermes/widgets/hermez_empty_chat_greeting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starter chips work without a Scaffold Material ancestor', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: HermezEmptyChatGreeting(
          greeting: 'Start chatting',
          starters: const ['Plan today', 'Research a topic'],
          onStarter: (value) => selected = value,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Plan today'));
    await tester.pump();
    expect(selected, 'Plan today');
    expect(tester.takeException(), isNull);
  });
  test('Hermez visuals are exclusive to debug Android Hermes chat', () {
    for (final debugBuild in [false, true]) {
      for (final android in [false, true]) {
        for (final hermes in [false, true]) {
          expect(
            shouldUseHermezChatVisuals(
              debugBuild: debugBuild,
              android: android,
              hermes: hermes,
            ),
            debugBuild && android && hermes,
          );
        }
      }
    }
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('greeting fits a narrow chat at 200% text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: HermezEmptyChatGreeting(
                  greeting: 'What would you like to make today?',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('HERMEZ'), findsOneWidget);
      expect(find.text('What would you like to make today?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        HermezChatPalette.forBrightness(brightness).canvas,
        isNot(HermezChatPalette.forBrightness(brightness).surface),
      );
    });
  }
}
