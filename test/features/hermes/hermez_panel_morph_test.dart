import 'dart:io';

import 'package:conduit/features/hermes/feedback/hermez_feedback.dart';
import 'package:conduit/features/hermes/motion/hermez_morph_origin.dart';
import 'package:conduit/features/hermes/motion/hermez_panel_morph.dart';
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

const _triggerKey = ValueKey('trigger');
const _insideKey = ValueKey('inside');
const _growKey = ValueKey('grow');

/// A button at the bottom-right that turns into a panel when tapped.
class _Harness extends StatefulWidget {
  const _Harness({this.reduceMotion = false});

  final bool reduceMotion;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int taps = 0;
  bool grown = false;
  bool? closedWith;

  Future<void> _open(BuildContext context) async {
    final origin = HermezMorphOrigin.of(
      context,
      radius: 16,
      color: const Color(0xFFE3192B),
    );
    if (origin == null) return;
    final result = await pushHermezPanel<bool>(
      context,
      origin: origin,
      originElevation: 2,
      surfaceColor: const Color(0xFFFFFFFF),
      semanticLabel: 'Test panel',
      faceBuilder: (context, progress) => const Center(
        child: Text('face', style: TextStyle(color: Colors.white)),
      ),
      builder: (panelContext) => StatefulBuilder(
        builder: (context, setPanel) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Panel title'),
              SizedBox(height: grown ? 300 : 60),
              TextButton(
                key: _insideKey,
                onPressed: () => setState(() => taps++),
                child: const Text('inside'),
              ),
              TextButton(
                key: _growKey,
                onPressed: () {
                  setState(() => grown = !grown);
                  setPanel(() {});
                },
                child: const Text('grow'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() => closedWith = result);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: widget.reduceMotion),
      child: child!,
    ),
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(
            right: 16,
            bottom: 16,
            child: Builder(
              builder: (context) => GestureDetector(
                key: _triggerKey,
                onTap: () => _open(context),
                child: Container(
                  width: 150,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3192B),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<RenderHermezPanelMorph> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_triggerKey));
  await tester.pump();
  return tester.renderObject<RenderHermezPanelMorph>(
    find.byType(HermezPanelMorph),
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

  Future<void> pumpHarness(
    WidgetTester tester, {
    bool reduceMotion = false,
    Size size = const Size(400, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_Harness(reduceMotion: reduceMotion));
  }

  test('the open curve bounces lightly and settles in about 0.4 s', () {
    final curve = HermezPanelMotion.open;
    expect(curve.peak, greaterThan(1.005));
    expect(curve.peak, lessThan(1.05));
    expect(curve.settleDuration.inMilliseconds, inInclusiveRange(300, 500));
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
  });

  testWidgets('starts as the button and ends as the panel', (tester) async {
    await pumpHarness(tester);
    final button = tester.getRect(find.byKey(_triggerKey));
    final render = await _open(tester);

    // First frame: the surface is exactly where the button was.
    await tester.pump();
    expect(render.originRect, button);
    expect(render.apertureRect.center.dx, closeTo(button.center.dx, 1));
    expect(render.apertureRect.center.dy, closeTo(button.center.dy, 1));
    expect(render.apertureRect.width, closeTo(button.width, 4));
    expect(find.text('face'), findsOneWidget);

    await tester.pumpAndSettle();
    // Settled: the surface is the panel, content-sized, top-anchored,
    // centred, 16 dp clear of each side.
    expect(render.apertureRect, render.panelRect);
    expect(render.panelRect.width, 368);
    expect(render.panelRect.left, 16);
    expect(render.panelRect.top, 12);
    expect(render.panelRect.height, greaterThan(100));
    expect(find.text('face'), findsNothing);
    expect(find.text('Panel title'), findsOneWidget);
  });

  testWidgets('grows through in-between shapes and bounces once', (
    tester,
  ) async {
    await pumpHarness(tester);
    final render = await _open(tester);
    final heights = <double>[];
    final tops = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      heights.add(render.apertureRect.height);
      tops.add(render.apertureRect.top);
    }
    await tester.pumpAndSettle();
    final finalHeight = render.panelRect.height;
    final peak = heights.reduce((a, b) => a > b ? a : b);

    // It really is in between, not a jump.
    expect(heights.any((h) => h > 60 && h < finalHeight - 20), isTrue);
    // A light bounce past the panel: over, but by a few percent at most.
    expect(peak, greaterThan(finalHeight));
    expect(peak, lessThan(finalHeight * 1.08));
    // The top edge travels up from the button to the top of the screen.
    expect(tops.first, greaterThan(tops.last));
    expect(render.apertureRect, render.panelRect);
  });

  testWidgets('nothing in the morph changes opacity', (tester) async {
    await pumpHarness(tester);
    await _open(tester);
    final fade = find.descendant(
      of: find.byType(HermezPanelMorph),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Opacity ||
            w is FadeTransition ||
            w is AnimatedOpacity ||
            w is FadeInImage,
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(fade, findsNothing);
    }
    await tester.pumpAndSettle();
    expect(fade, findsNothing);
  });

  testWidgets('the face is shown only while the panel is not fully open', (
    tester,
  ) async {
    await pumpHarness(tester);
    await _open(tester);
    expect(find.text('face'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('face'), findsNothing);

    // Closing brings it back before the surface has reached the button.
    await tester.tapAt(const Offset(200, 780));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('face'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HermezPanelMorph), findsNothing);
  });

  testWidgets('input waits until the panel is at rest', (tester) async {
    await pumpHarness(tester);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-flight the content is on screen but does not take taps.
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    await tester.tap(find.byKey(_insideKey), warnIfMissed: false);
    await tester.pump();
    expect(state.taps, 0);

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_insideKey));
    await tester.pump();
    expect(state.taps, 1);
  });

  testWidgets('tapping outside runs it home into the button and reports '
      'the result only afterwards', (tester) async {
    await pumpHarness(tester);
    final button = tester.getRect(find.byKey(_triggerKey));
    final render = await _open(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(state.closedWith, isNull);

    await tester.tapAt(const Offset(200, 780));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // On its way home: smaller than the panel, larger than the button.
    expect(render.apertureRect.height, lessThan(render.panelRect.height));
    expect(render.apertureRect.height, greaterThan(button.height));
    expect(state.closedWith, isNull);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(HermezPanelMorph), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel follows its content, top edge fixed', (tester) async {
    await pumpHarness(tester);
    final render = await _open(tester);
    await tester.pumpAndSettle();
    final top = render.panelRect.top;
    final height = render.panelRect.height;

    await tester.tap(find.byKey(_growKey));
    await tester.pump();
    await tester.pump();
    expect(render.panelRect.top, top);
    expect(render.panelRect.height, height + 240);
    // At rest the surface is the panel on the same frame: it does not lag.
    expect(render.apertureRect, render.panelRect);

    await tester.tap(find.byKey(_growKey));
    await tester.pump();
    await tester.pump();
    expect(render.panelRect.height, height);
    expect(render.apertureRect, render.panelRect);
  });

  testWidgets('reduced motion opens and closes at once', (tester) async {
    await pumpHarness(tester, reduceMotion: true);
    final render = await _open(tester);
    expect(render.apertureRect, render.panelRect);
    expect(find.text('face'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tapAt(const Offset(200, 780));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HermezPanelMorph), findsNothing);
  });

  testWidgets('the panel stays above the keyboard and scrolls its own '
      'content', (tester) async {
    await pumpHarness(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    final render = await _open(tester);
    await tester.pumpAndSettle();
    expect(render.panelRect.bottom, lessThanOrEqualTo(800 - 300 - 12 + 0.01));
    expect(render.apertureRect, render.panelRect);
  });

  testWidgets('accessibility: the panel names the route; the face is not '
      'announced', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHarness(tester);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.bySemanticsLabel('face'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Test panel'), findsWidgets);
    expect(find.bySemanticsLabel('inside'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a soft latch plays when it goes home, not at reduced '
      'motion', (tester) async {
    await pumpHarness(tester);
    await _open(tester);
    await tester.pumpAndSettle();
    final before = sound.played.length;
    await tester.tapAt(const Offset(200, 780));
    await tester.pumpAndSettle();
    expect(sound.played.length, before + 1);
  });

  test('the morph piece carries no business logic', () {
    final source = File('lib/features/hermes/motion/hermez_panel_morph.dart')
        .readAsStringSync();
    for (final banned in [
      'kanban',
      'hermes_desktop',
      'providers/',
      'services/',
      'Opacity',
      'FadeTransition',
      'AnimatedOpacity',
    ]) {
      expect(source.contains(banned), isFalse, reason: banned);
    }
  });
}
