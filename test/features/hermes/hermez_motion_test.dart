import 'dart:math' as math;

import 'package:conduit/features/hermes/motion/hermez_motion.dart';
import 'package:conduit/features/hermes/widgets/hermez_sheet_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Hermez spring keeps moving until it settles, then ends at 1', () {
    for (final weight in HermezMotionWeight.values) {
      final curve = HermezMotion.curveFor(weight);
      // No dead hold: an overshooting spring clamped to 1 used to sit still
      // for the second half of its duration and then snap when it ended.
      expect(curve.transform(0.7), lessThan(0.999), reason: '$weight');
      expect(curve.transform(0.99), greaterThan(0.99), reason: '$weight');
      expect(curve.transform(1), 1);
      var previous = 0.0;
      for (var i = 1; i <= 200; i++) {
        final value = curve.transform(i / 200);
        expect(value, greaterThanOrEqualTo(previous), reason: '$weight');
        // Continuous: no frame jumps more than a small step near the end.
        if (i > 150) expect(value - previous, lessThan(0.01));
        previous = value;
      }
    }
  });

  test('route curves are shared, not created per frame', () {
    final controller = AnimationController(vsync: const TestVSync());
    addTearDown(controller.dispose);
    expect(
      identical(
        hermezCurved(controller, HermezMotion.curveMedium),
        hermezCurved(controller, HermezMotion.curveMedium),
      ),
      isTrue,
    );
    expect(
      identical(
        hermezCurved(controller, HermezMotion.curveMedium),
        hermezCurved(
          controller,
          HermezMotion.curveMedium,
          reverseOf: HermezMotion.curveLight,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('the screen under a route keeps one structure for every cover', (
    tester,
  ) async {
    Widget covered(HermezCoverKind kind) => MaterialApp(
      home: HermezCoveredTransition(
        kind: kind,
        animation: kAlwaysDismissedAnimation,
        child: const Text('Home', key: ValueKey('home')),
      ),
    );
    await tester.pumpWidget(covered(HermezCoverKind.shift));
    final element = tester.element(find.byKey(const ValueKey('home')));
    for (final kind in [
      HermezCoverKind.recede,
      HermezCoverKind.lift,
      HermezCoverKind.none,
    ]) {
      await tester.pumpWidget(covered(kind));
      // Same element: switching the cover did not remount the page.
      expect(tester.element(find.byKey(const ValueKey('home'))), same(element));
    }
  });

  test('bot morph ids stay unique to the profile', () {
    expect(hermezBotMorphId('kai'), 'bot:kai');
    expect(hermezBotMorphId('local'), 'bot:local');
    expect(hermezBotMorphId('kai'), isNot(hermezBotMorphId('local')));
    expect(hermezBotMorphId(''), isNull);
    expect(hermezBotMorphId('Not A Profile'), isNull);
    expect(hermezMorphPart('bot:kai', 'mark'), 'bot:kai#mark');
    expect(hermezMorphPart(null, 'mark'), isNull);
  });

  test('source ids come from model ids, never list positions', () {
    expect(hermezKanbanTaskMorphId('main', 't1'), 'kanban:main:t1');
    expect(hermezKanbanTaskMorphId(null, 't1'), isNull);
    expect(hermezKanbanTaskMorphId('main', ''), isNull);
    expect(
      hermezArtifactMorphId('/opt/data/a.png'),
      'artifact:/opt/data/a.png',
    );
    expect(hermezArtifactMorphId(''), isNull);
    expect(hermezJobMorphId('kai', 'job-1'), 'job:kai:job-1');
    expect(hermezJobMorphId('kai', null), isNull);
    expect(hermezBrowserMorphId('s1'), 'session:s1:browser');
  });

  test('spring curves start and end at rest', () {
    for (final weight in HermezMotionWeight.values) {
      final curve = HermezMotion.curveFor(weight);
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      expect(curve.transform(0.5), greaterThan(0.5));
      expect(curve.transform(0.98), closeTo(1, 0.01));
    }
  });

  test('heavier objects settle slower and compress less', () {
    expect(
      HermezMotion.settleFor(HermezMotionWeight.light),
      lessThan(HermezMotion.settleFor(HermezMotionWeight.medium)),
    );
    expect(
      HermezMotion.settleFor(HermezMotionWeight.medium),
      lessThan(HermezMotion.settleFor(HermezMotionWeight.heavy)),
    );
    expect(
      HermezMotion.settleFor(HermezMotionWeight.heavy),
      lessThan(const Duration(milliseconds: 700)),
    );
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

  test('a page grows from its origin and otherwise slides in', () {
    final withOrigin = HermezRoute<void>(
      builder: (_) => const SizedBox(),
      motion: HermezRouteMotion.expand,
      origin: const HermezMorphOrigin.rect(Rect.fromLTWH(10, 10, 100, 80)),
    );
    expect(withOrigin.effectiveMotion, HermezRouteMotion.expand);
    // The source stays painted underneath so Back contracts immediately.
    expect(withOrigin.opaque, isFalse);

    final withoutOrigin = HermezRoute<void>(
      builder: (_) => const SizedBox(),
      motion: HermezRouteMotion.expand,
    );
    expect(withoutOrigin.effectiveMotion, HermezRouteMotion.standard);

    final sheet = HermezRoute<void>(
      builder: (_) => const SizedBox(),
      motion: HermezRouteMotion.expand,
      shape: HermezExpandShape.sheet,
    );
    expect(sheet.effectiveMotion, HermezRouteMotion.expand);
    expect(sheet.opaque, isFalse);
    expect(sheet.barrierDismissible, isTrue);

    final reduced = HermezRoute<void>(
      builder: (_) => const SizedBox(),
      motion: HermezRouteMotion.expand,
      origin: const HermezMorphOrigin.rect(Rect.zero),
      reducedMotion: true,
    );
    expect(reduced.effectiveMotion, HermezRouteMotion.none);
    expect(reduced.transitionDuration, Duration.zero);
  });

  test('schedule weekdays come only from plain weekly cron patterns', () {
    expect(hermezCronWeekdays('0 9 * * 1-5'), {1, 2, 3, 4, 5});
    expect(hermezCronWeekdays('0 9 * * *'), {1, 2, 3, 4, 5, 6, 7});
    expect(hermezCronWeekdays('30 7 * * sat,sun'), {6, 7});
    expect(hermezCronWeekdays('0 9 * * 0'), {7});
    expect(hermezCronWeekdays('0 9 1 * *'), isNull);
    expect(hermezCronWeekdays('every morning'), isNull);
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
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a motion surface reports its origin when opening', (
    tester,
  ) async {
    HermezMorphOrigin? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 60,
              child: HermezMotionSurface(
                onOpen: (origin) => opened = origin,
                child: const Text('Kai'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kai'));
    await tester.pumpAndSettle();
    expect(opened, isNotNull);
    expect(opened!.resolve().size, const Size(120, 60));
  });

  testWidgets('a scroll that starts on a surface does not open it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var index = 0; index < 20; index++)
                SizedBox(
                  height: 90,
                  child: HermezMotionSurface(
                    onTap: () => taps++,
                    child: Text('Row $index'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.text('Row 2'), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(taps, 0);
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

  testWidgets('a motion surface is a button for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HermezMotionSurface(
            semanticLabel: 'Open Kai',
            onTap: () => taps++,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Open Kai'));
    expect(node.flagsCollection.isButton, isTrue);
    tester.semantics.tap(find.semantics.byLabel('Open Kai'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('morph parts use one hero tag and reduced motion skips it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            HermezMorph(id: 'bot:kai#mark', child: Text('mark')),
            HermezMorphText(
              'Kai',
              id: 'bot:kai#name',
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
    final tags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag)
        .toSet();
    expect(tags, {'bot:kai#mark', 'bot:kai#name'});

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Column(
            children: [
              HermezMorph(id: 'bot:kai#mark', child: Text('mark')),
              HermezMorphText(
                'Kai',
                id: 'bot:kai#name',
                style: TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.text('Kai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expanding page zooms out of its card as one object', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: SizedBox(
                width: 200,
                height: 120,
                child: HermezMotionSurface(
                  onOpen: (origin) => Navigator.of(context).push(
                    HermezRoute<void>(
                      motion: HermezRouteMotion.expand,
                      origin: origin,
                      builder: (_) => const Scaffold(
                        body: Align(
                          alignment: Alignment.topLeft,
                          child: HermezMorphText(
                            'Kai page',
                            id: 'bot:kai#name',
                            style: TextStyle(fontSize: 34),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const HermezMorphText(
                    'Kai card',
                    id: 'bot:kai#name',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kai card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // The whole page is scaled into the card: its title is smaller than at
    // rest and sits inside the card, not on a separate flight path.
    final early = tester.getRect(find.text('Kai page'));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.text('Kai page'));
    expect(early.width, lessThan(rest.width));
    expect(early.left, greaterThan(rest.left));
    expect(rest.topLeft, Offset.zero);

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(find.text('Kai page')).width, lessThan(rest.width));
    await tester.pumpAndSettle();
    expect(find.text('Kai page'), findsNothing);
    expect(find.text('Kai card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a title flies between theme and Hermez text styles', (
    tester,
  ) async {
    // Theme text styles use inherit: false; Hermez styles inherit. The
    // flight must interpolate across that without throwing.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(
          body: HermezMorphText(
            'Kanban',
            id: 'kanban:summary#title',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      HermezRoute<void>(
        builder: (_) => const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: HermezMorphText(
              'Kanban',
              id: 'kanban:summary#title',
              style: TextStyle(inherit: false, fontSize: 36),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('Kanban'), findsOneWidget);
  });

  testWidgets('a sheet grows out of its card and contracts back into it', (
    tester,
  ) async {
    // The sheet page stays at the navigator origin, so Hero flights land
    // where the sheet's title really is and never float above the sheet.
    final navigator = GlobalKey<NavigatorState>();
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Align(
            alignment: const Alignment(0, 0.6),
            child: Builder(
              builder: (context) => HermezMotionSurface(
                onOpen: (origin) => pushHermezSheet<void>(
                  context,
                  origin: origin,
                  builder: (_) => const Material(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: HermezMorphText(
                          'Task sheet',
                          id: 'kanban:b:t#title',
                          style: TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const HermezMorphText(
                  'Task',
                  id: 'kanban:b:t#title',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final start = tester.getTopLeft(find.text('Task')).dy;
    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();
    final landed = tester.getTopLeft(find.text('Task sheet')).dy;
    navigator.currentState!.pop();
    await tester.pump();
    var faceShown = false;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final y = tester.getTopLeft(find.text('Task sheet')).dy;
      // It never jumps above its path; near the card it leaves downward
      // through the card's edge instead of being swapped on the last frame.
      expect(y, greaterThanOrEqualTo(math.min(start, landed) - 1));
      faceShown |= find.byType(RawImage).evaluate().isNotEmpty;
    }
    // The card's own face was uncovered before the route ended.
    expect(faceShown, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sheet pushes the screen above it up, and pulls it down', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        onGenerateRoute: (_) => HermezRoute<void>(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 40),
                const Text('Screen top'),
                const Spacer(),
                const Text('Above the card'),
                HermezMotionSurface(
                  onOpen: (origin) => pushHermezSheet<void>(
                    context,
                    origin: origin,
                    builder: (_) => const Material(child: Text('Sheet body')),
                  ),
                  child: const SizedBox(
                    width: 200,
                    height: 80,
                    child: Center(child: Text('Card')),
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double top() => tester.getTopLeft(find.text('Screen top')).dy;
    final rest = top();
    final card = tester.getRect(find.byType(HermezMotionSurface));

    await tester.tap(find.text('Card'));
    await tester.pump();
    // Rising, never falling back, while the sheet grows.
    var previous = rest;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(top(), lessThanOrEqualTo(previous + 0.01));
      previous = top();
    }
    await tester.pumpAndSettle();
    // Pushed up by exactly as far as the sheet's top edge rose above the
    // card: the content right above the card stays against the sheet.
    final sheetTop = tester.getTopLeft(find.text('Sheet body')).dy;
    expect(rest - top(), closeTo(card.top - sheetTop, 1));

    // Dragging the sheet down pulls the screen down with it.
    final pushed = top();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Sheet body')),
    );
    await gesture.moveBy(const Offset(0, 60));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(top() - pushed, closeTo(120, 20));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(top(), closeTo(pushed, 1));

    navigator.currentState!.pop();
    await tester.pump();
    previous = top();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(top(), greaterThanOrEqualTo(previous - 0.01));
      previous = top();
    }
    await tester.pumpAndSettle();
    // Back exactly where it was.
    expect(top(), rest);
    expect(tester.takeException(), isNull);
  });

  test('a card widens first, then its top edge rises to the sheet', () {
    const card = Rect.fromLTWH(100, 700, 200, 80);
    const sheet = Rect.fromLTWH(0, 40, 400, 860);
    expect(hermezSheetAperture(card, sheet, 0), card);
    final widened = hermezSheetAperture(card, sheet, 0.3);
    expect(widened.left, 0);
    expect(widened.right, 400);
    expect(widened.top, card.top);
    final rising = hermezSheetAperture(card, sheet, 0.7);
    expect(rising.top, lessThan(card.top));
    expect(rising.top, greaterThan(sheet.top));
    expect(hermezSheetAperture(card, sheet, 1), sheet);
  });

  testWidgets('a sheet can be dragged down to close', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Scaffold()),
    );
    var closed = false;
    pushHermezSheet<void>(
      navigator.currentContext!,
      builder: (_) => const ColoredBox(
        color: Colors.white,
        child: Center(child: Text('Sheet')),
      ),
    ).then((_) => closed = true);
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);
    await tester.fling(find.text('Sheet'), const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsNothing);
    expect(closed, isTrue);
  });
}
