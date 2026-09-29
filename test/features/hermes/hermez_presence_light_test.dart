import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_live_activity.dart';
import 'package:conduit/features/hermes/widgets/hermez_bot_mark.dart';
import 'package:conduit/features/hermes/widgets/hermez_bot_presence.dart';
import 'package:conduit/features/hermes/widgets/hermez_surfaces.dart';
import 'package:conduit/features/hermes/widgets/hermez_touch_light.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HermesLiveActivityEvent _event(HermesLiveActivityKind kind) =>
    HermesLiveActivityEvent(
      sessionId: 's',
      kind: kind,
      title: kind.name,
      timestamp: DateTime(2026, 9, 29),
    );

void main() {
  test('bot state comes only from the reported turn and activity', () {
    const running = HermesDesktopTurnState.running;
    expect(
      hermezBotVisualStateFor(HermesDesktopTurnState.idle, [
        _event(HermesLiveActivityKind.waitingForInput),
      ]),
      HermezBotVisualState.idle,
    );
    expect(hermezBotVisualStateFor(running, []), HermezBotVisualState.active);
    expect(
      hermezBotVisualStateFor(running, [
        _event(HermesLiveActivityKind.toolStarted),
      ]),
      HermezBotVisualState.active,
    );
    expect(
      hermezBotVisualStateFor(running, [
        _event(HermesLiveActivityKind.waitingForInput),
      ]),
      HermezBotVisualState.waiting,
    );
    // Reconnecting is not a live turn.
    expect(
      hermezBotVisualStateFor(HermesDesktopTurnState.reconnecting, []),
      HermezBotVisualState.idle,
    );
  });

  group('presence motion', () {
    setUp(() => HermezBotPresence.loopsEnabled = true);
    tearDown(() => HermezBotPresence.loopsEnabled = false);

    Offset markOffset(WidgetTester tester) =>
        tester.getTopLeft(find.byType(HermezBotMark)).translate(0, 0);

    testWidgets('a hero mark floats a little, without any fade', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: HermezBotPresence(identity: HermezBotIdentity.kai, size: 88),
          ),
        ),
      );
      final start = markOffset(tester);
      final seen = <double>{};
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        seen.add((markOffset(tester).dy - start.dy).roundToDouble());
      }
      expect(seen.length, greaterThan(1));
      for (final dy in seen) {
        expect(dy.abs(), lessThanOrEqualTo(2));
      }
      expect(
        find.descendant(
          of: find.byType(HermezBotPresence),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('small marks stay still when idle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: HermezBotPresence(
              identity: HermezBotIdentity.fast,
              size: 46,
            ),
          ),
        ),
      );
      final start = markOffset(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(markOffset(tester), start);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion keeps a hero mark still', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(
              child: HermezBotPresence(
                identity: HermezBotIdentity.strong,
                size: 88,
              ),
            ),
          ),
        ),
      );
      final start = markOffset(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(markOffset(tester), start);
    });
  });

  group('touch light', () {
    Widget card(VoidCallback onTap) => HermezSurface(
      touchLight: true,
      semanticLabel: 'Kai',
      onTap: onTap,
      child: const SizedBox(height: 120),
    );

    testWidgets('a tap still fires exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SizedBox(width: 200, child: card(() => taps++))),
        ),
      );
      expect(find.byType(HermezTouchLight), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Kai'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('a scroll that starts on a lit card still scrolls, and does '
        'not tap', (tester) async {
      var taps = 0;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: [
              card(() => taps++),
              for (var i = 0; i < 20; i++) const SizedBox(height: 80),
            ],
          ),
        ),
      );
      await tester.drag(find.bySemanticsLabel('Kai'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(200));
      expect(taps, 0);
    });

    testWidgets('reduced motion shows no light', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Center(child: SizedBox(width: 200, child: card(() {}))),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(HermezTouchLight),
          matching: find.byType(Listener),
        ),
        findsNothing,
      );
    });
  });
}
