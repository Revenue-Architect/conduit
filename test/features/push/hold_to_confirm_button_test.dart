import 'package:checks/checks.dart';
import 'package:conduit/features/push/views/hold_to_confirm_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
);

void main() {
  const hold = Duration(milliseconds: 1000);

  testWidgets('a quick tap does not confirm', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    await tester.tap(find.byType(HoldToConfirmButton));
    await tester.pump(const Duration(milliseconds: 400));
    check(confirmed).equals(0);
  });

  testWidgets('releasing before the time is up cancels', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    check(confirmed).equals(0);
    // Holding again must start from empty, not from where it stopped.
    final again = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 500));
    check(confirmed).equals(0);
    await again.up();
  });

  testWidgets('holding the full time confirms exactly once', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 500));
    check(confirmed).equals(0);
    await tester.pump(const Duration(milliseconds: 600));
    check(confirmed).equals(1);
    // Keep holding: no repeat.
    await tester.pump(const Duration(seconds: 2));
    check(confirmed).equals(1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    check(confirmed).equals(1);
  });

  testWidgets('shows progress and a holding label while pressed', (tester) async {
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdingLabel: 'Keep holding...',
          holdDuration: hold,
          onConfirmed: () {},
        ),
      ),
    );
    check(find.text('Hold to approve').evaluate()).isNotEmpty();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 400));
    check(find.text('Keep holding...').evaluate()).isNotEmpty();
    final fill = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    check(fill.widthFactor!).isGreaterThan(0.2);
    check(fill.widthFactor!).isLessThan(0.7);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    final drained = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    check(drained.widthFactor!).equals(0);
  });

  testWidgets('sliding the finger away cancels the hold', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 1500));
    check(confirmed).equals(0);
    await gesture.up();
  });

  testWidgets('disabled and busy buttons ignore presses', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          enabled: false,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    check(confirmed).equals(0);

    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          busy: true,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    final busyGesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(); // first frame starts the hold ticker
    await tester.pump(const Duration(seconds: 2));
    await busyGesture.up();
    check(confirmed).equals(0);
    check(find.byType(CircularProgressIndicator).evaluate()).isNotEmpty();
  });

  testWidgets('screen readers get a long-press action', (tester) async {
    final handle = tester.ensureSemantics();
    var confirmed = 0;
    await tester.pumpWidget(
      _host(
        HoldToConfirmButton(
          label: 'Hold to approve',
          holdDuration: hold,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(HoldToConfirmButton));
    check(node.label).contains('Hold to approve');
    check(node.hint).contains('hold');
    tester.semantics.longPress(find.semantics.byLabel('Hold to approve'));
    await tester.pump();
    check(confirmed).equals(1);
    handle.dispose();
  });
}
