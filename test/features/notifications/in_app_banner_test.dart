import 'package:conduit/features/notifications/views/in_app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final navigator = GlobalKey<NavigatorState>();

  Future<void> pumpPages(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('chat')),
      ),
    );
    // A page with its own Scaffold covers the first one, as Kanban does.
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('kanban'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(HermezInAppBanner.hide);

  testWidgets('shows above a page pushed over the chat and opens on tap', (
    tester,
  ) async {
    await pumpPages(tester);
    var opened = 0;
    HermezInAppBanner.show(
      navigator.currentState!.overlay!,
      title: 'fast finished',
      body: 'It is 17 degrees in Toronto.',
      onOpen: () => opened++,
    );
    await tester.pumpAndSettle();
    expect(find.text('fast finished'), findsOneWidget);
    expect(find.text('kanban'), findsOneWidget);

    await tester.tap(find.text('fast finished'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('fast finished'), findsNothing);
  });

  testWidgets('leaves on its own and on a swipe up', (tester) async {
    await pumpPages(tester);
    HermezInAppBanner.show(
      navigator.currentState!.overlay!,
      title: 'first',
      body: '',
      onOpen: () {},
      duration: const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);

    HermezInAppBanner.show(
      navigator.currentState!.overlay!,
      title: 'second',
      body: '',
      onOpen: () {},
    );
    await tester.pumpAndSettle();
    await tester.fling(find.text('second'), const Offset(0, -80), 800);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('a new banner replaces the one showing', (tester) async {
    await pumpPages(tester);
    final overlay = navigator.currentState!.overlay!;
    HermezInAppBanner.show(overlay, title: 'one', body: '', onOpen: () {});
    await tester.pumpAndSettle();
    HermezInAppBanner.show(overlay, title: 'two', body: '', onOpen: () {});
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
    HermezInAppBanner.hide();
    await tester.pump(const Duration(seconds: 6));
  });
}
