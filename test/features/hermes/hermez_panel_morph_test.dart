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
const _screen = Size(400, 800);

/// A button that turns into a panel when tapped, bottom-right by default.
class _Harness extends StatefulWidget {
  const _Harness({this.reduceMotion = false, this.topLeft = false});

  final bool reduceMotion;
  final bool topLeft;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int taps = 0;
  bool grown = false;
  bool? closedWith;
  final turns = <double>[];

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
      faceBuilder: (context, turn) {
        turns.add(turn);
        return const Center(
          child: Text('face', style: TextStyle(color: Colors.white)),
        );
      },
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
            right: widget.topLeft ? null : 16,
            bottom: widget.topLeft ? null : 16,
            left: widget.topLeft ? 16 : null,
            top: widget.topLeft ? 100 : null,
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

RenderHermezPanelMorph _morph(WidgetTester tester) =>
    tester.renderObject<RenderHermezPanelMorph>(find.byType(HermezPanelMorph));

Future<RenderHermezPanelMorph> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_triggerKey));
  await tester.pump();
  return _morph(tester);
}

double _opacityAbove(WidgetTester tester, Finder finder) {
  final opacity = find.ancestor(of: finder, matching: find.byType(Opacity));
  return tester.widget<Opacity>(opacity.first).opacity;
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
    bool topLeft = false,
  }) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _Harness(reduceMotion: reduceMotion, topLeft: topLeft),
    );
  }

  test('the motion tokens are those of the Dropdown menu morph', () {
    expect(HermezPanelMotion.openDuration, const Duration(milliseconds: 350));
    expect(HermezPanelMotion.closeDuration, const Duration(milliseconds: 250));
    expect(HermezPanelMotion.fadeDuration, const Duration(milliseconds: 200));
    expect(HermezPanelMotion.openEase, const Cubic(0.34, 1.25, 0.64, 1));
    expect(HermezPanelMotion.closeEase, const Cubic(0.22, 1, 0.36, 1));
    expect(HermezPanelMotion.openRadius, 20);
    expect(HermezPanelMotion.slide, 40);
    expect(HermezPanelMotion.scale, 0.97);
    expect(HermezPanelMotion.blur, 2);
  });

  test('each property keeps its own timing, both ways', () {
    // Opening, at the end of the 200 ms fade the content is fully in while
    // the size (350 ms, overshooting ease) is still travelling.
    final fadeDone = HermezMorphFrame.of(200 / 350, opening: true);
    expect(fadeDone.fade, closeTo(1, 0.001));
    expect(fadeDone.size, lessThan(1.1));
    expect(fadeDone.move, lessThan(1));
    // The open size overshoots past the panel before settling.
    var peak = 0.0;
    for (var i = 0; i <= 350; i++) {
      final f = HermezMorphFrame.of(i / 350, opening: true);
      if (f.size > peak) peak = f.size;
    }
    expect(peak, greaterThan(1.01));
    // Closing, 200 ms of the 250 ms in, the content is fully out and the
    // surface is nearly home.
    final closing = HermezMorphFrame.of(1 - 200 / 250, opening: false);
    expect(closing.fade, closeTo(0, 0.001));
    expect(closing.size, lessThan(0.1));
    expect(HermezMorphFrame.of(0, opening: false).size, closeTo(0, 1e-9));
  });

  testWidgets('the button itself expands in place: anchored at its corner, '
      'growing toward the screen', (tester) async {
    await pumpHarness(tester);
    final button = tester.getRect(find.byKey(_triggerKey));
    final morph = await _open(tester);

    // First frame: the surface is exactly the button.
    await tester.pump();
    expect(morph.originRect, button);
    expect(morph.apertureRect.left, closeTo(button.left, 1));
    expect(morph.apertureRect.bottom, closeTo(button.bottom, 1));

    // Mid-flight it is still attached to the button's bottom-right corner.
    await tester.pump(const Duration(milliseconds: 120));
    expect(morph.apertureRect.right, closeTo(button.right, 3));
    expect(morph.apertureRect.bottom, closeTo(button.bottom, 3));
    expect(morph.apertureRect.width, greaterThan(button.width));
    expect(morph.apertureRect.height, greaterThan(button.height));

    await tester.pumpAndSettle();
    // Open: the panel shares the button's corner and grew up and left.
    expect(morph.anchoredBottom, isTrue);
    expect(morph.apertureRect, morph.panelRect);
    expect(morph.panelRect.right, button.right);
    expect(morph.panelRect.bottom, button.bottom);
    expect(morph.panelRect.width, 368);
    expect(find.text('face'), findsNothing);
    expect(find.text('Panel title'), findsOneWidget);
  });

  testWidgets('a button near the top grows downward from its top corner', (
    tester,
  ) async {
    await pumpHarness(tester, topLeft: true);
    final button = tester.getRect(find.byKey(_triggerKey));
    final morph = await _open(tester);
    await tester.pumpAndSettle();
    expect(morph.anchoredBottom, isFalse);
    expect(morph.panelRect.top, button.top);
    expect(morph.panelRect.left, button.left);
  });

  testWidgets('the plus fades, blurs, slides and turns; the content fades '
      'and sharpens in', (tester) async {
    await pumpHarness(tester);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 60));

    final faceOpacity = _opacityAbove(tester, find.text('face'));
    final contentOpacity = _opacityAbove(tester, find.text('Panel title'));
    expect(faceOpacity, inExclusiveRange(0, 1));
    expect(contentOpacity, inExclusiveRange(0, 1));
    expect(faceOpacity + contentOpacity, closeTo(1, 0.001));
    final blurs = tester.widgetList<ImageFiltered>(find.byType(ImageFiltered));
    expect(blurs.where((b) => b.enabled), hasLength(2));
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(state.turns.last, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.text('face'), findsNothing);
    expect(_opacityAbove(tester, find.text('Panel title')), 1);
    expect(
      tester
          .widgetList<ImageFiltered>(find.byType(ImageFiltered))
          .where((b) => b.enabled),
      isEmpty,
    );
  });

  testWidgets('input waits until the panel is at rest', (tester) async {
    await pumpHarness(tester);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    await tester.tap(find.byKey(_insideKey), warnIfMissed: false);
    await tester.pump();
    expect(state.taps, 0);

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_insideKey));
    await tester.pump();
    expect(state.taps, 1);
  });

  testWidgets('tapping outside runs it home into the button in 250 ms and '
      'reports the result only afterwards', (tester) async {
    await pumpHarness(tester);
    final button = tester.getRect(find.byKey(_triggerKey));
    final morph = await _open(tester);
    await tester.pumpAndSettle();
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    await tester.tapAt(const Offset(200, 60));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(morph.apertureRect.height, lessThan(morph.panelRect.height));
    expect(morph.apertureRect.height, greaterThan(button.height));
    expect(find.text('face'), findsOneWidget);
    expect(state.closedWith, isNull);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byType(HermezPanelMorph), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel follows its content, anchored edge fixed', (
    tester,
  ) async {
    await pumpHarness(tester);
    final morph = await _open(tester);
    await tester.pumpAndSettle();
    final bottom = morph.panelRect.bottom;
    final height = morph.panelRect.height;

    await tester.tap(find.byKey(_growKey));
    await tester.pump();
    await tester.pump();
    expect(morph.panelRect.bottom, bottom);
    expect(morph.panelRect.height, height + 240);
    expect(morph.apertureRect, morph.panelRect);
  });

  testWidgets('with the keyboard up the whole panel sits above it', (
    tester,
  ) async {
    await pumpHarness(tester);
    final morph = await _open(tester);
    await tester.pumpAndSettle();
    final restingBottom = morph.panelRect.bottom;

    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(morph.panelRect.bottom, lessThanOrEqualTo(800 - 300 - 12 + 0.01));
    expect(morph.panelRect.bottom, lessThan(restingBottom));
    expect(morph.apertureRect, morph.panelRect);
  });

  testWidgets('reduced motion opens and closes at once', (tester) async {
    await pumpHarness(tester, reduceMotion: true);
    final morph = await _open(tester);
    expect(morph.apertureRect, morph.panelRect);
    expect(find.text('face'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tapAt(const Offset(200, 60));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HermezPanelMorph), findsNothing);
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

  testWidgets('a soft latch plays when it goes home', (tester) async {
    await pumpHarness(tester);
    await _open(tester);
    await tester.pumpAndSettle();
    final before = sound.played.length;
    await tester.tapAt(const Offset(200, 60));
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
    ]) {
      expect(source.contains(banned), isFalse, reason: banned);
    }
  });
}
