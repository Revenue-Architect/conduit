import 'package:conduit/features/hermes/kanban/hermes_kanban_summary_provider.dart';
import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_api_service.dart';
import 'package:conduit/features/hermes/views/hermes_attention_page.dart';
import 'package:conduit/features/hermes/views/hermes_bot_detail_page.dart';
import 'package:conduit/features/hermes/views/hermes_home_page.dart';
import 'package:conduit/features/hermes/views/hermes_live_run_page.dart';
import 'package:conduit/features/navigation/widgets/responsive_drawer_layout.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Home menu button slides Home aside to the side navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final layout = GlobalKey<ResponsiveDrawerLayoutState>();
    final router = GoRouter(
      initialLocation: Routes.hermesHome,
      routes: [
        GoRoute(
          path: Routes.hermesHome,
          // What the Home route builds on phones, with a stand-in sidebar.
          builder: (context, state) => ResponsiveDrawerLayout(
            key: layout,
            mobileRailLabel: const Text('HOME'),
            mobileRailSemanticLabel: 'Return to Home',
            drawer: const Material(child: Center(child: Text('Sidebar'))),
            child: const HermesHomePage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesApiServiceProvider.overrideWithValue(null),
          hermesBotsProvider.overrideWith((ref) async => []),
          hermesHomeProfileJobsProvider.overrideWith((ref) async => []),
          hermesSessionsProvider.overrideWith(_EmptySessionsController.new),
          hermesKanbanSummaryProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('hermes-home-navigation-toggle'));
    expect(toggle, findsOneWidget);
    expect(layout.currentState!.isOpen, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(layout.currentState!.isOpen, isTrue);
    expect(tester.getTopLeft(find.byType(HermesHomePage)).dx, 390);
    expect(find.bySemanticsLabel('Return to Home'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('side-nav-return-rail')));
    await tester.pumpAndSettle();
    expect(layout.currentState!.isOpen, isFalse);
    expect(tester.getTopLeft(find.byType(HermesHomePage)).dx, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Scheduled agents opens the full list when jobs exist', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: Routes.hermesHome,
      routes: [
        GoRoute(
          path: Routes.hermesHome,
          builder: (context, state) => const HermesHomePage(),
        ),
        GoRoute(
          path: Routes.hermesJobs,
          name: RouteNames.hermesJobs,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('All scheduled agents'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    NavigationService.attachRouter(router);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesApiServiceProvider.overrideWithValue(null),
          hermesBotsProvider.overrideWith((ref) async => []),
          hermesHomeProfileJobsProvider.overrideWith(
            (ref) async => [
              (
                'kai',
                HermesJob(
                  id: 'job-1',
                  name: 'Daily research digest',
                  prompt: 'Summarize research',
                  schedule: '0 9 * * *',
                  enabled: true,
                ),
              ),
            ],
          ),
          hermesSessionsProvider.overrideWith(_EmptySessionsController.new),
          hermesKanbanSummaryProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scheduled agents'));
    await tester.tap(find.text('Scheduled agents'));
    await tester.pumpAndSettle();
    expect(find.text('All scheduled agents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home recent row opens its exact conversation', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
    addTearDown(PreferencesStore.debugReset);
    final service = _RecentSessionService();
    final router = GoRouter(
      initialLocation: Routes.hermesHome,
      routes: [
        GoRoute(
          path: Routes.hermesHome,
          builder: (context, state) => const HermesHomePage(),
        ),
        GoRoute(
          path: Routes.chat,
          builder: (context, state) => const Scaffold(body: Text('Chat route')),
        ),
        GoRoute(
          path: Routes.hermesConversations,
          builder: (context, state) =>
              const Scaffold(body: Text('Conversations route')),
        ),
      ],
    );
    addTearDown(router.dispose);
    NavigationService.attachRouter(router);
    final container = ProviderContainer(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(service),
        hermesBotsProvider.overrideWith((ref) async => const []),
        hermesSessionsProvider.overrideWith(_LoadedSessionsController.new),
        hermesKanbanSummaryProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Roadmap ideas'));
    await tester.tap(find.text('Roadmap ideas'));
    await tester.pumpAndSettle();
    expect(service.openedIds, ['session-1']);
    expect(container.read(hermesActiveSessionProvider), 'session-1');
    expect(find.text('Chat route'), findsOneWidget);
    expect(find.text('Conversations route'), findsNothing);
  });

  testWidgets(
    'Home renders real bot/job/session shapes at 320 px and 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesApiServiceProvider.overrideWithValue(null),
            hermesBotsProvider.overrideWith(
              (ref) async => const [
                HermesBot(
                  name: 'kai',
                  title: 'Kai',
                  description: 'Creative projects and ideas',
                ),
                HermesBot(
                  name: 'default',
                  title: 'Default',
                  description: 'General-purpose assistant',
                ),
              ],
            ),
            hermesSessionsProvider.overrideWith(_LoadedSessionsController.new),
            hermesJobsProvider.overrideWith(_LoadedJobsController.new),
            hermesKanbanSummaryProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const HermesHomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kai'), findsOneWidget);
      expect(find.text('LIVE WORK'), findsNothing);
      await tester.drag(
        find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Live Run stays bounded with a Desktop Gateway service at 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = HermesDesktopApiService(
        config: const HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example/v1',
          mode: HermesBackendMode.desktopGateway,
          desktopAuthKind: HermesDesktopAuthKind.nativePkce,
        ),
      );
      addTearDown(service.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermesApiServiceProvider.overrideWithValue(service),
            hermesSessionsProvider.overrideWith(_EmptySessionsController.new),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const HermesLiveRunPage(sessionId: 'sample-session'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      // The run's honest state, not a decorative ring.
      expect(find.text('NOT RUNNING'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Hermes destinations show safe empty states at $width px / $scale text',
        (tester) async {
          tester.view.physicalSize = Size(width, 820);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          for (final page in <Widget>[
            const HermesHomePage(),
            const HermesBotDetailPage(profile: 'kai'),
            const HermesAttentionPage(),
            const HermesLiveRunPage(sessionId: 'sample-session'),
          ]) {
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  hermesApiServiceProvider.overrideWithValue(null),
                  hermesBotsProvider.overrideWith((ref) async => []),
                  hermesKanbanSummaryProvider.overrideWith((ref) async => null),
                ],
                child: MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: page,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.runtimeType} at $width px / $scale text',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
      );
    }
  }
}

class _RecentSessionService extends HermesApiService {
  _RecentSessionService()
    : super(
        config: const HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          apiKey: 'test-key',
        ),
      );

  final openedIds = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getSessionMessages(
    String id, {
    CancelToken? cancelToken,
  }) async {
    openedIds.add(id);
    return [
      {'role': 'assistant', 'content': 'Saved response'},
    ];
  }
}

class _EmptySessionsController extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => [];
}

class _LoadedSessionsController extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [
    HermesSessionSummary(
      id: 'session-1',
      title: 'Roadmap ideas',
      profile: 'kai',
    ),
  ];
}

class _LoadedJobsController extends HermesJobsController {
  @override
  Future<List<HermesJob>> build() async => [
    HermesJob(
      id: 'job-1',
      name: 'Daily research digest',
      prompt: 'Research',
      schedule: '0 9 * * *',
      nextRun: DateTime.now().add(const Duration(hours: 1)),
    ),
  ];
}
