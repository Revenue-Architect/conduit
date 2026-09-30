import 'package:conduit/features/navigation/widgets/responsive_drawer_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'responsive_drawer_layout_test_support.dart';

void main() {
  testWidgets('Back pops a page opened over the open drawer instead of being '
      'swallowed by the covered drawer', (tester) async {
    await tester.binding.setSurfaceSize(drawerTestMobileSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final layoutKey = GlobalKey<ResponsiveDrawerLayoutState>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ResponsiveDrawerLayout(
            key: layoutKey,
            drawer: const ColoredBox(
              color: Colors.blue,
              child: SizedBox.expand(),
            ),
            child: const ColoredBox(
              color: Colors.orange,
              child: SizedBox.expand(),
            ),
          ),
        ),
        GoRoute(
          path: '/page',
          builder: (context, state) =>
              const Scaffold(body: Text('opened from the drawer')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await drawerTestOpenDrawer(tester, layoutKey);

    router.push('/page');
    await tester.pumpAndSettle();
    expect(find.text('opened from the drawer'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('opened from the drawer'), findsNothing);
  });
}
