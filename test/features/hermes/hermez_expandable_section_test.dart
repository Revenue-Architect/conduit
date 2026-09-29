import 'dart:io';

import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/widgets/hermez_expandable_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sound implements HermezSoundBackend {
  final List<String> played = [];

  @override
  Future<void> start(Iterable<String> assets) async {}

  @override
  void play(String asset, {required double volume, required double speed}) =>
      played.add(asset.split('/').last);
}

/// A parent that owns the expanded state, as the primitive requires.
class _Host extends StatefulWidget {
  const _Host({this.initial = false, this.reduceMotion = false});

  final bool initial;
  final bool reduceMotion;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool expanded = widget.initial;
  int childTaps = 0;

  void set(bool value) => setState(() => expanded = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: widget.reduceMotion),
      child: Scaffold(
        body: ListView(
          children: [
            HermezExpandableSection(
              expanded: expanded,
              onExpansionChanged: set,
              semanticLabel: 'Systems',
              openFeedback: HermezFeedbackCue.compartmentOpen,
              closeFeedback: HermezFeedbackCue.compartmentClose,
              header: const Text('SYSTEMS / 3'),
              child: Column(
                children: [
                  const SizedBox(height: 120, child: Text('email')),
                  TextButton(
                    onPressed: () => setState(() => childTaps++),
                    child: const Text('calendar'),
                  ),
                ],
              ),
            ),
            const Text('KNOWLEDGE', key: ValueKey('below')),
          ],
        ),
      ),
    ),
  );
}

void main() {
  late _Sound sound;
  late HermezFeedback previous;

  setUp(() async {
    sound = _Sound();
    previous = HermezFeedback.instance;
    final feedback = HermezFeedback.forTesting(
      backend: sound,
      haptic: (_) async {},
    );
    await feedback.startForTesting();
    HermezFeedback.instance = feedback;
  });
  tearDown(() => HermezFeedback.instance = previous);

  double belowY(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const ValueKey('below'))).dy;

  _HostState host(WidgetTester tester) => tester.state(find.byType(_Host));

  testWidgets('opening pushes the content below down; closing brings it '
      'back', (tester) async {
    await tester.pumpWidget(const _Host());
    final closedY = belowY(tester);
    expect(find.text('email'), findsNothing); // unmounted while closed

    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midY = belowY(tester);
    await tester.pumpAndSettle();
    final openY = belowY(tester);
    expect(midY, greaterThan(closedY));
    expect(openY, greaterThan(midY));
    expect(host(tester).expanded, isTrue);

    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pumpAndSettle();
    expect(belowY(tester), closedY);
    expect(find.text('email'), findsNothing);
  });

  testWidgets('a second tap mid-flight reverses from where it is', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    final closedY = belowY(tester);
    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final beforeReverse = belowY(tester);
    expect(beforeReverse, greaterThan(closedY));

    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pump();
    // No jump to open, no snap to closed.
    expect((belowY(tester) - beforeReverse).abs(), lessThan(12));
    await tester.pump(const Duration(milliseconds: 80));
    final after = belowY(tester);
    expect(after, lessThan(beforeReverse + 12));
    await tester.pumpAndSettle();
    expect(belowY(tester), closedY);
  });

  testWidgets('the parent owns the state: it can open without a tap, and that '
      'plays no sound', (tester) async {
    await tester.pumpWidget(const _Host());
    final closedY = belowY(tester);
    host(tester).set(true);
    await tester.pumpAndSettle();
    expect(belowY(tester), greaterThan(closedY));
    expect(find.text('email'), findsOneWidget);
    expect(sound.played, isEmpty);
  });

  testWidgets('an initially open section builds open and silent', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(initial: true));
    await tester.pump();
    expect(find.text('email'), findsOneWidget);
    expect(sound.played, isEmpty);
  });

  testWidgets('feedback plays once per real toggle', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pumpAndSettle();
    expect(sound.played, ['object_open.wav', 'object_close.wav']);
  });

  testWidgets('semantics: expanded state, and hidden content is unreachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Systems'))),
      matchesSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(find.bySemanticsLabel('calendar'), findsNothing);

    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Systems'))),
      matchesSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(find.bySemanticsLabel('calendar'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('content takes input only while open', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('calendar'));
    await tester.pump();
    expect(host(tester).childTaps, 1);

    // Closing: mid-flight the rows are still drawn but take no taps.
    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('calendar'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(host(tester).childTaps, 1);
  });

  testWidgets('reduced motion changes the layout at once', (tester) async {
    await tester.pumpWidget(const _Host(reduceMotion: true));
    final closedY = belowY(tester);
    await tester.tap(find.text('SYSTEMS / 3'));
    await tester.pump();
    final openY = belowY(tester);
    expect(openY, greaterThan(closedY + 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('the primitive carries no business logic', () {
    final source = File(
      'lib/features/hermes/widgets/hermez_expandable_section.dart',
    ).readAsStringSync();
    for (final banned in [
      'hermes_desktop_api_service',
      'hermes_job',
      'hermes_bot.dart',
      'kanban',
      'providers/',
      'services/',
    ]) {
      expect(source.contains(banned), isFalse, reason: banned);
    }
  });
}
