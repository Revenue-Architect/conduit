import 'package:conduit/features/hermes/models/hermes_todo.dart';
import 'package:conduit/features/hermes/widgets/hermes_plan_view.dart';
import 'package:conduit/features/hermes/widgets/hermez_commit_button.dart';
import 'package:conduit/features/hermes/widgets/hermez_live.dart';
import 'package:conduit/features/hermes/widgets/hermez_segments.dart';
import 'package:conduit/features/hermes/widgets/hermez_skeleton.dart';
import 'package:conduit/features/hermes/widgets/hermez_status_morph.dart';
import 'package:conduit/shared/widgets/chrome_gradient_fade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  group('status morph', () {
    testWidgets('moves through every state without losing itself', (
      tester,
    ) async {
      var state = HermezMorphState.idle;
      late StateSetter set;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return HermezStatusMorph(state: state, semanticLabel: 'Run');
            },
          ),
        ),
      );
      for (final next in [
        HermezMorphState.working,
        HermezMorphState.done,
        HermezMorphState.working,
        HermezMorphState.failed,
        HermezMorphState.attention,
        HermezMorphState.idle,
      ]) {
        set(() => state = next);
        await tester.pumpAndSettle();
        expect(find.byType(HermezStatusMorph), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('spins and resolves with live motion on', (tester) async {
      HermezLiveMotion.enabled = true;
      addTearDown(() => HermezLiveMotion.enabled = false);
      var state = HermezMorphState.working;
      late StateSetter set;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return HermezStatusMorph(state: state);
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      set(() => state = HermezMorphState.failed);
      // The ring closes, floods and draws; the nudge plays once.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('skeleton', () {
    testWidgets('reads as loading and lays out its bones', (tester) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              HermezSkeleton.rows(count: 3),
              HermezSkeleton.lines(count: 2),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('Loading'), findsNWidgets(2));
      expect(find.byType(HermezBone), findsNWidgets(3 * 3 + 2));
    });

    testWidgets('sweeps while live motion is on', (tester) async {
      HermezLiveMotion.enabled = true;
      addTearDown(() => HermezLiveMotion.enabled = false);
      await tester.pumpWidget(_app(HermezSkeleton.rows(count: 2)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // A sheen that stops working leaves the text exactly as it was.
      await tester.pumpWidget(
        _app(const HermezSheen(active: false, child: Text('Thinking'))),
      );
      expect(find.text('Thinking'), findsOneWidget);
    });
  });

  group('commit button', () {
    testWidgets('works, says so, then hands over', (tester) async {
      var committed = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: HermezCommitButton(
              label: 'Create task',
              successLabel: 'Created',
              hold: const Duration(milliseconds: 400),
              onCommit: () async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
                return true;
              },
              onCommitted: () => committed++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Create task'));
      await tester.pump();
      expect(find.bySemanticsLabel('Create task, working'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('Created'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 450));
      expect(committed, 1);
    });

    testWidgets('failure says so and taps again to retry', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: HermezCommitButton(
              label: 'Save',
              onCommit: () async {
                attempts++;
                if (attempts == 1) throw StateError('offline');
                return true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      // Success with no label of its own shows only the check, then returns.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('segments', () {
    Future<List<int>> mount(WidgetTester tester) async {
      final changes = <int>[];
      var index = 0;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => HermezSegments(
              labels: const ['Model', 'Effort', 'Speed'],
              index: index,
              onChanged: (i) {
                changes.add(i);
                setState(() => index = i);
              },
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('a tap selects', (tester) async {
      final changes = await mount(tester);
      await tester.tap(find.text('Effort').first);
      await tester.pumpAndSettle();
      expect(changes, [1]);
    });

    testWidgets('the block drags, resists past the end, and settles', (
      tester,
    ) async {
      final changes = await mount(tester);
      final block = tester.getCenter(find.text('Model').first);
      final width = tester.getSize(find.byType(HermezSegments)).width / 3;
      await tester.dragFrom(block, Offset(width * 1.1, 0));
      await tester.pumpAndSettle();
      expect(changes, [1]);
      // Far past the last segment: it stops at the last one.
      final now = tester.getCenter(find.text('Effort').first);
      await tester.dragFrom(now, Offset(width * 4, 0));
      await tester.pumpAndSettle();
      expect(changes.last, 2);
    });
  });

  test('plan rails join steps at the same depth', () {
    HermesTodoRow row(String id, HermesTodoStatus status, {int depth = 0}) => (
      item: HermesTodoItem(id: id, content: id, status: status),
      depth: depth,
    );
    final done = row('a', HermesTodoStatus.completed);
    final cancelled = row('b', HermesTodoStatus.cancelled);
    final next = row('c', HermesTodoStatus.pending);
    expect(hermesPlanRailBetween(done, next), HermesPlanRail.done);
    expect(hermesPlanRailBetween(cancelled, next), HermesPlanRail.stopped);
    expect(hermesPlanRailBetween(next, done), HermesPlanRail.pending);
    expect(hermesPlanRailBetween(done, null), isNull);
    expect(
      hermesPlanRailBetween(done, row('d', HermesTodoStatus.pending, depth: 1)),
      isNull,
    );
  });

  testWidgets('plan rows draw their rails', (tester) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            HermesPlanRow(
              item: const HermesTodoItem(
                id: 'a',
                content: 'Check the date',
                status: HermesTodoStatus.completed,
              ),
              railBelow: HermesPlanRail.done,
              onTap: () {},
            ),
            const HermesPlanRow(
              item: HermesTodoItem(
                id: 'b',
                content: 'Reply briefly',
                status: HermesTodoStatus.inProgress,
              ),
              railAbove: HermesPlanRail.done,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Check the date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chrome edge can frost what scrolls under it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          height: 200,
          child: Stack(
            children: [
              Positioned.fill(child: Text('Message under the bar')),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: ConduitChromeGradientFade.top(
                  contentHeight: 96,
                  backgroundColor: Colors.white,
                  blurSigma: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Full frost behind the bar, then a feather that thins to nothing.
    expect(find.byType(BackdropFilter), findsWidgets);
    final blurs = tester
        .widgetList<BackdropFilter>(find.byType(BackdropFilter))
        .length;
    expect(blurs, greaterThan(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the frost is gone by its extent', (tester) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          height: 300,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: ConduitChromeGradientFade.top(
                  contentHeight: 96,
                  backgroundColor: Colors.white,
                  blurSigma: 5,
                  blurExtent: 96,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final top = tester.getTopLeft(find.byType(ConduitChromeGradientFade)).dy;
    final lowest = tester
        .widgetList<BackdropFilter>(find.byType(BackdropFilter))
        .map((filter) => tester.getBottomLeft(find.byWidget(filter)).dy)
        .reduce((a, b) => a > b ? a : b);
    // Nothing blurs below the extent; the gradient still reaches further.
    expect(lowest - top, lessThanOrEqualTo(96.01));
  });
}
