import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/hermes/motion/hermez_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bot morph ids stay unique to the profile', () {
    expect(hermezBotMorphId('kai'), 'bot:kai');
    expect(hermezBotMorphId('local'), 'bot:local');
    expect(hermezBotMorphId('kai'), isNot(hermezBotMorphId('local')));
    expect(hermezBotMorphId(''), isNull);
    expect(hermezBotMorphId('Not A Profile'), isNull);
  });

  test('only bot detail uses the morph route', () {
    expect(
      hermezRouteMotionFor(RouteNames.hermesBotDetail),
      HermezRouteMotion.morph,
    );
    expect(
      hermezRouteMotionFor(RouteNames.hermesHome),
      HermezRouteMotion.standard,
    );
    expect(
      hermezRouteMotionFor(RouteNames.hermesJobs),
      HermezRouteMotion.standard,
    );
  });

  test('heavier objects compress less than lighter ones', () {
    expect(
      HermezMotion.pressScale(HermezMotionWeight.light),
      lessThan(HermezMotion.pressScale(HermezMotionWeight.medium)),
    );
    expect(
      HermezMotion.pressScale(HermezMotionWeight.medium),
      lessThan(HermezMotion.pressScale(HermezMotionWeight.heavy)),
    );
    expect(HermezMotion.pressScale(HermezMotionWeight.heavy), lessThan(1));
  });

  testWidgets('a motion surface invokes its action once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HermezMotionSurface(
            semanticLabel: 'Kai',
            onTap: () => taps++,
            child: const Text('Kai'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kai'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a disabled motion surface does not fire', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HermezMotionSurface(
            enabled: false,
            onTap: () => taps++,
            child: const Text('Kai'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kai'));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('morph uses one hero tag and reduced motion skips the flight', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HermezMorph(id: 'bot:kai', child: Text('Kai')),
      ),
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, 'bot:kai');

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: HermezMorph(id: 'bot:kai', child: Text('Kai')),
        ),
      ),
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.text('Kai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
