import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: a long Hermes sheet is the full-height card. It rests, springs
  // up to raised when dragged up, and closes when dragged below resting. A
  // short one (fit) is the card sized to its content.
  testWidgets(
    'full-height card snaps between two detents; fit sizes to content',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late BuildContext app;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              app = context;
              return const Scaffold();
            },
          ),
        ),
      );
      final screen = tester.view.physicalSize.height / 3;

      double cardHeight() =>
          tester.getSize(find.byType(HermezModalSheet)).height;

      pushHermezSheetRoute<void>(
        app,
        builder: (_) => const HermezModalSheet(
          title: 'Plan',
          body: SizedBox(height: 2000, child: Text('steps')),
        ),
      );
      await tester.pumpAndSettle();
      final resting = cardHeight();
      expect(resting, closeTo(screen * 0.62, 2));

      final grabber =
          tester.getTopLeft(find.byType(HermezModalSheet)) +
          const Offset(180, 12);
      await tester.flingFrom(grabber, const Offset(0, -300), 1500);
      await tester.pumpAndSettle();
      expect(cardHeight(), closeTo(screen * 0.91, 2));

      await tester.flingFrom(
        tester.getTopLeft(find.byType(HermezModalSheet)) +
            const Offset(180, 12),
        const Offset(0, 300),
        1500,
      );
      await tester.pumpAndSettle();
      expect(cardHeight(), closeTo(resting, 2));

      await tester.dragFrom(
        tester.getTopLeft(find.byType(HermezModalSheet)) +
            const Offset(180, 12),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HermezModalSheet), findsNothing);

      pushHermezSheetRoute<void>(
        app,
        fit: true,
        builder: (_) => const HermezModalSheet(
          title: 'Choose a bot',
          body: SizedBox(height: 120, child: Text('Chief')),
        ),
      );
      await tester.pumpAndSettle();
      expect(cardHeight(), lessThan(screen * 0.45));
      expect(find.text('Chief'), findsOneWidget);
    },
  );
}
