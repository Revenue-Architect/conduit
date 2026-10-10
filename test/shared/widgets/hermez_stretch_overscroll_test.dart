import 'package:conduit/shared/widgets/hermez_stretch_overscroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list({bool disallow = false}) {
  Widget list = ListView(
    children: [
      for (var i = 0; i < 4; i++)
        SizedBox(height: 100, child: Text('row $i')),
    ],
  );
  if (disallow) {
    list = NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        notification.disallowIndicator();
        return false;
      },
      child: list,
    );
  }
  return MaterialApp(
    scrollBehavior: const HermezScrollBehavior(),
    home: Scaffold(body: list),
  );
}

/// Vertical travel of the content, in logical pixels.
double _travel(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(HermezStretchOverscroll),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .getTranslation()
    .y;

/// The give is a pure translation: no scale, so text is never re-rasterised.
void _expectNoScale(WidgetTester tester) {
  final matrix = tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(HermezStretchOverscroll),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform;
  expect(matrix.getMaxScaleOnAxis(), 1.0);
}

Future<void> _pullDown(WidgetTester tester, TestGesture gesture) async {
  for (var i = 0; i < 6; i++) {
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
  }
}

void main() {
  testWidgets('Android overscroll gives by moving, then settles home', (
    tester,
  ) async {
    await tester.pumpWidget(_list());
    // Flutter's stretch renders the viewport into an offscreen layer.
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(HermezStretchOverscroll), findsOneWidget);
    expect(_travel(tester), 0.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 1')),
    );
    await _pullDown(tester, gesture);
    final travel = _travel(tester);
    final viewport = tester.getSize(find.byType(ListView)).height;
    expect(travel, greaterThan(0.0));
    expect(
      travel,
      lessThanOrEqualTo(viewport * HermezStretchOverscroll.maxStretch + 0.5),
    );
    _expectNoScale(tester);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_travel(tester), 0.0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('an ancestor can disallow the stretch (sheet drag)', (
    tester,
  ) async {
    await tester.pumpWidget(_list(disallow: true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 1')),
    );
    await _pullDown(tester, gesture);
    expect(_travel(tester), 0.0);
    await gesture.up();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
