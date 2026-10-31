import 'package:conduit/features/hermes/motion/hermez_card_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: nothing opened from a card opens anything new. A nested step
  // reshapes the same card, and typed input survives going in and back.
  testWidgets('nested steps stay in one card and keep typed text', (
    tester,
  ) async {
    final observer = _RouteCount();
    late BuildContext inCard;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: HermezCardStack(
            root: HermezCardView(
              title: 'New chat',
              builder: (context) {
                inCard = context;
                return const TextField(key: Key('message'));
              },
            ),
          ),
        ),
      ),
    );
    final routesAtStart = observer.pushes;
    await tester.enterText(find.byKey(const Key('message')), 'Scale my recipe');

    HermezCardStack.of(inCard).push(
      HermezCardView(title: 'Attach', builder: (_) => const Text('Photos')),
    );
    await tester.pumpAndSettle();
    HermezCardStack.of(inCard).push(
      HermezCardView(
        title: 'Umbrel files',
        builder: (_) => const Text('sourdough.pdf'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HermezCardStack), findsOneWidget);
    expect(find.text('Umbrel files'), findsOneWidget);
    expect(observer.pushes, routesAtStart);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('Scale my recipe'), findsOneWidget);
    expect(observer.pushes, routesAtStart);
  });
}

class _RouteCount extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}
