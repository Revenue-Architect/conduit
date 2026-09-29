import 'package:conduit/features/navigation/widgets/physical_side_nav.dart';
import 'package:conduit/features/navigation/widgets/responsive_drawer_layout.dart';
import 'package:conduit/shared/widgets/sidebar_layout_contract.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

const _phone = Size(390, 844);

class _ChatProbe extends StatefulWidget {
  const _ChatProbe();

  static int created = 0;

  @override
  State<_ChatProbe> createState() => _ChatProbeState();
}

class _ChatProbeState extends State<_ChatProbe> {
  final TextEditingController composer = TextEditingController();
  final ScrollController messages = ScrollController();

  @override
  void initState() {
    super.initState();
    _ChatProbe.created++;
  }

  @override
  void dispose() {
    composer.dispose();
    messages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('chat-surface'),
    child: Column(
      children: [
        Expanded(
          child: ListView.builder(
            key: const ValueKey('messages'),
            controller: messages,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 40, child: Text('m$i')),
          ),
        ),
        TextField(key: const ValueKey('composer'), controller: composer),
      ],
    ),
  );
}

class _NavProbe extends StatelessWidget {
  const _NavProbe();

  @override
  Widget build(BuildContext context) => Material(
    child: Column(
      children: [
        const SideNavItem(index: 0, child: Text('Conduit')),
        SideNavItem(
          index: 1,
          child: TextButton(
            // A destination: selecting it closes the side navigation.
            onPressed: () => closeSidebarDrawerIfOverlay(context),
            child: const Text('Chats'),
          ),
        ),
      ],
    ),
  );
}

GlobalKey<ResponsiveDrawerLayoutState> _layoutKey =
    GlobalKey<ResponsiveDrawerLayoutState>();

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = _phone,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _layoutKey = GlobalKey<ResponsiveDrawerLayoutState>();
  _ChatProbe.created = 0;
  final router = GoRouter(
    initialLocation: '/chat',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'chat',
            builder: (context, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: ResponsiveDrawerLayout(
                key: _layoutKey,
                mobileRailLabel: const Text('CHAT'),
                mobileRailSemanticLabel: 'Return to chat',
                drawer: const _NavProbe(),
                child: const _ChatProbe(),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

double _chatX(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('chat-surface'))).dx;

Rect _rail(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('side-nav-return-rail')));

bool _ignoring(WidgetTester tester, Finder of) => tester
    .widget<IgnorePointer>(
      find.ancestor(of: of, matching: find.byType(IgnorePointer)).first,
    )
    .ignoring;

void main() {
  group('geometry', () {
    test('closed', () {
      final g = sideNavGeometryFor(viewport: const Size(390, 844), progress: 0);
      expect(g.chatOffset, 0);
      expect(g.cornerRadius, 0);
      expect(g.verticalInset, 0);
      expect(g.railInteractive, isFalse);
      expect(g.navigationInteractive, isFalse);
      expect(g.chatInteractive, isTrue);
      expect(g.navigationOffset, closeTo(-0.36 * 346, 0.001));
    });

    test('halfway', () {
      final g = sideNavGeometryFor(
        viewport: const Size(390, 844),
        progress: 0.5,
      );
      expect(g.chatOffset, closeTo(195, 0.001));
      expect(g.railRect.left, closeTo(151, 0.001));
      expect(g.railRect.right, closeTo(195, 0.001));
      expect(g.cornerRadius, closeTo(8, 0.001));
      expect(g.verticalInset, closeTo(7, 0.001));
      expect(g.navigationOffset, closeTo(-0.18 * 346, 0.001));
    });

    test('open', () {
      final g = sideNavGeometryFor(viewport: const Size(390, 844), progress: 1);
      expect(g.chatOffset, 390);
      expect(g.railRect.left, closeTo(346, 0.001));
      expect(g.railRect.width, 44);
      expect(g.railRect.top, 14);
      expect(g.railRect.bottom, 844 - 14);
      expect(g.cornerRadius, 16);
      expect(g.verticalInset, 14);
      expect(g.navigationOffset, 0);
      expect(g.navigationInteractive, isTrue);
      expect(g.chatInteractive, isFalse);
      expect(g.railInteractive, isTrue);
    });

    test('the rail takes touches once about 2 px of it is exposed', () {
      const viewport = Size(390, 844);
      expect(
        sideNavGeometryFor(
          viewport: viewport,
          progress: 1 / 390,
        ).railInteractive,
        isFalse,
      );
      expect(
        sideNavGeometryFor(
          viewport: viewport,
          progress: 2 / 390,
        ).railInteractive,
        isTrue,
      );
    });

    test('moving offsets land on whole device pixels', () {
      for (final value in [0.0, 12.34, 195.13, -62.28, 389.99]) {
        final snapped = snapToDevicePixels(value, 3.75);
        expect(snapped * 3.75, closeTo((snapped * 3.75).roundToDouble(), 1e-9));
        expect((snapped - value).abs(), lessThanOrEqualTo(0.5 / 3.75 + 1e-9));
      }
      expect(snapToDevicePixels(195, 1), 195);
    });

    test('labels stagger by 30 ms and finish together, both ways', () {
      expect(sideNavItemProgress(0, 0), 0);
      expect(sideNavItemProgress(1, 5), 1);
      final step = 30 / 520;
      expect(sideNavItemProgress(step, 1), 0);
      expect(sideNavItemProgress(0.5, 0), 0.5);
      expect(
        sideNavItemProgress(0.5, 3),
        lessThan(sideNavItemProgress(0.5, 1)),
      );
      // Continuous: no step anywhere along the way.
      for (var i = 0; i < 100; i++) {
        final a = sideNavItemProgress(i / 100, 2);
        final b = sideNavItemProgress((i + 1) / 100, 2);
        expect(b - a, lessThan(0.02));
        expect(b, greaterThanOrEqualTo(a));
      }
    });
  });

  testWidgets('closed: chat in place, navigation and rail inert', (
    tester,
  ) async {
    await _pumpShell(tester);
    expect(_chatX(tester), 0);
    expect(_ignoring(tester, find.text('Chats')), isTrue);
    expect(
      _ignoring(tester, find.byKey(const ValueKey('side-nav-return-rail'))),
      isTrue,
    );
    expect(_layoutKey.currentState!.isOpen, isFalse);
    // No clip at rest.
    final clip = tester.widget<ClipRect>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('chat-surface')),
            matching: find.byType(ClipRect),
          )
          .first,
    );
    expect(clip.clipBehavior, Clip.none);
  });

  testWidgets('open: chat off to the right, rail on the edge, nav live', (
    tester,
  ) async {
    await _pumpShell(tester);
    _layoutKey.currentState!.toggle();
    await tester.pumpAndSettle();
    expect(_layoutKey.currentState!.isOpen, isTrue);
    expect(_chatX(tester), 390);
    expect(_rail(tester).left, closeTo(346, 0.01));
    expect(_rail(tester).width, 44);
    expect(_rail(tester).top, 14);
    expect(_ignoring(tester, find.text('Chats')), isFalse);
    expect(find.bySemanticsLabel('Return to chat'), findsOneWidget);
    // Over the solid stage the surface is inset by a rectangular clip and
    // rounded by painted corners, never an anti-aliased rounded clip.
    final surface = find.byKey(const ValueKey('chat-surface'));
    expect(
      find.ancestor(of: surface, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    final clip = tester.getRect(
      find.ancestor(of: surface, matching: find.byType(ClipRect)).first,
    );
    expect(clip.left, 390);
  });

  testWidgets('the motion runs 520 ms on one curve, halfway geometry', (
    tester,
  ) async {
    await _pumpShell(tester);
    _layoutKey.currentState!.open();
    await tester.pump();
    // Where the curve crosses one half, the chat is half a screen across.
    var t = 0.0;
    while (kSideNavCurve.transform(t) < 0.5) {
      t += 0.001;
    }
    await tester.pump(kSideNavDuration * t);
    expect(_chatX(tester), closeTo(195, 4));
    expect(_rail(tester).right, closeTo(_chatX(tester), 0.5));
    await tester.pump(kSideNavDuration * (1 - t));
    expect(_chatX(tester), 390);
  });

  testWidgets('toggling mid-open reverses from where it is', (tester) async {
    await _pumpShell(tester);
    final nav = _layoutKey.currentState!;
    nav.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final mid = _chatX(tester) / 390;
    expect(mid, inInclusiveRange(0.25, 0.75));
    nav.toggle();
    await tester.pump();
    // No jump at the reversal frame, then heading back.
    expect((_chatX(tester) / 390 - mid).abs(), lessThan(0.02));
    await tester.pump(const Duration(milliseconds: 32));
    expect(_chatX(tester) / 390, lessThan(mid));
    await tester.pumpAndSettle();
    expect(_chatX(tester), 0);
    expect(nav.isOpen, isFalse);
  });

  testWidgets('toggling mid-close reopens from where it is', (tester) async {
    await _pumpShell(tester);
    final nav = _layoutKey.currentState!;
    nav.open();
    await tester.pumpAndSettle();
    nav.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final mid = _chatX(tester) / 390;
    expect(mid, inInclusiveRange(0.25, 0.75));
    nav.toggle();
    await tester.pump();
    expect((_chatX(tester) / 390 - mid).abs(), lessThan(0.02));
    await tester.pump(const Duration(milliseconds: 32));
    expect(_chatX(tester) / 390, greaterThan(mid));
    await tester.pumpAndSettle();
    expect(_chatX(tester), 390);
    expect(nav.isOpen, isTrue);
  });

  testWidgets('the rail and a destination both close the navigation', (
    tester,
  ) async {
    await _pumpShell(tester);
    _layoutKey.currentState!.open();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('side-nav-return-rail')));
    await tester.pumpAndSettle();
    expect(_chatX(tester), 0);

    _layoutKey.currentState!.open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    expect(_chatX(tester), 0);
  });

  testWidgets('opening and closing keeps the chat, its scroll, and composer', (
    tester,
  ) async {
    await _pumpShell(tester);
    await tester.enterText(find.byKey(const ValueKey('composer')), 'draft');
    final state = tester.state<_ChatProbeState>(find.byType(_ChatProbe));
    state.messages.jumpTo(1200);
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      _layoutKey.currentState!.open();
      await tester.pumpAndSettle();
      _layoutKey.currentState!.close();
      await tester.pumpAndSettle();
    }
    expect(_ChatProbe.created, 1);
    expect(identical(tester.state(find.byType(_ChatProbe)), state), isTrue);
    expect(state.composer.text, 'draft');
    expect(state.messages.offset, 1200);
  });

  testWidgets('Android back closes the navigation and keeps the chat', (
    tester,
  ) async {
    await _pumpShell(tester);
    _layoutKey.currentState!.open();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_chatX(tester), 0);
    expect(find.byType(_ChatProbe), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('a settled open state follows a new viewport', (tester) async {
    await _pumpShell(tester);
    _layoutKey.currentState!.open();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(_chatX(tester), 844);
    expect(_rail(tester).left, closeTo(800, 0.01));
    expect(_rail(tester).height, 390 - 28);
  });

  testWidgets('reduced motion reaches the same states at once', (tester) async {
    await _pumpShell(tester, reduceMotion: true);
    _layoutKey.currentState!.open();
    await tester.pump();
    expect(_chatX(tester), 390);
    expect(_layoutKey.currentState!.isOpen, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_chatX(tester), 0);
  });

  testWidgets('navigation labels slide in with the motion, no fade', (
    tester,
  ) async {
    await _pumpShell(tester);
    double lagOf(String text) => tester
        .widget<Transform>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Transform))
              .first,
        )
        .transform
        .getTranslation()
        .x;
    expect(lagOf('Conduit'), -SideNavItem.shift);
    _layoutKey.currentState!.open();
    await tester.pump();
    // The first item is never behind the second, and ahead of it on some
    // frames: the stagger (offsets are whole pixels, so some frames tie).
    var led = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(lagOf('Conduit'), greaterThanOrEqualTo(lagOf('Chats')));
      led = led || lagOf('Conduit') > lagOf('Chats');
    }
    expect(led, isTrue);
    // Motion only: nothing in the navigation fades.
    expect(
      find.ancestor(of: find.text('Chats'), matching: find.byType(Opacity)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(lagOf('Conduit'), 0);
    expect(lagOf('Chats'), 0);
  });

  testWidgets('the navigation can be drawn in the opposite theme', (
    tester,
  ) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<ResponsiveDrawerLayoutState>();
    Brightness? navigationBrightness;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: ResponsiveDrawerLayout(
          key: key,
          mobileNavigationTheme: ThemeData(brightness: Brightness.dark),
          drawer: Builder(
            builder: (context) {
              navigationBrightness = Theme.of(context).brightness;
              return const SizedBox.expand();
            },
          ),
          child: const _ChatProbe(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(navigationBrightness, Brightness.dark);
    expect(
      Theme.of(tester.element(find.byType(_ChatProbe))).brightness,
      Brightness.light,
    );
    // The system bars follow the navigation's brightness only while it
    // rests open (and until it has closed), never part-way through.
    final region = find.byWidgetPredicate(
      (widget) =>
          widget is AnnotatedRegion<SystemUiOverlayStyle> &&
          widget.value.statusBarIconBrightness == Brightness.light,
    );
    expect(region, findsOneWidget);
    Size regionSize() => tester.getSize(region);
    expect(regionSize(), Size.zero);
    key.currentState!.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(regionSize(), Size.zero);
    await tester.pumpAndSettle();
    expect(regionSize(), _phone);
    key.currentState!.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(regionSize(), _phone);
    await tester.pumpAndSettle();
    expect(regionSize(), Size.zero);
  });
}
