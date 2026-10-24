import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_summary_provider.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_team.dart';
import 'package:conduit/features/hermes/motion/hermez_morph_origin.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/views/hermes_attention_page.dart';
import 'package:conduit/features/hermes/views/hermes_teams_page.dart';
import 'package:conduit/features/hermes/views/hermes_work_page.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_presence.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:conduit/features/push/providers/push_providers.dart'
    show approvalsPendingProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bots = [
  HermesBot(name: 'default', title: 'Default'),
  HermesBot(name: 'kai', title: 'Kai'),
];

final _opened = <String, Object?>{};
final _params = <String, Map<String, String>>{};

GoRouter _router() {
  GoRoute dest(String path, String name) => GoRoute(
    path: path,
    name: name,
    builder: (context, state) {
      _opened[name] = state.extra;
      _params[name] = state.pathParameters;
      return Scaffold(body: Center(child: Text('dest:$name')));
    },
  );
  return GoRouter(
    initialLocation: Routes.hermesHome,
    routes: [
      GoRoute(
        path: Routes.hermesHome,
        builder: (context, state) => const HermesWorkPage(),
      ),
      dest(Routes.hermesJobs, RouteNames.hermesJobs),
      dest(Routes.hermesKanban, RouteNames.hermesKanban),
      dest(Routes.hermesTeams, RouteNames.hermesTeams),
      dest(Routes.hermesArtifacts, RouteNames.hermesArtifacts),
      dest(Routes.hermesAttention, RouteNames.hermesAttention),
      dest(Routes.hermesApprovals, RouteNames.hermesApprovals),
      dest(Routes.hermesSettings, RouteNames.hermesSettings),
      dest(Routes.hermesBotDetail, RouteNames.hermesBotDetail),
    ],
  );
}

HermesKanbanSummary _board() => HermesKanbanSummary(
  const KanbanBoardRef('default', 'Main', 4),
  KanbanSnapshot.fromJson('default', {
    'columns': [
      {
        'name': 'todo',
        'tasks': [
          {'id': 't1'},
          {'id': 't2'},
        ],
      },
      {
        'name': 'running',
        'tasks': [
          {'id': 't3'},
        ],
      },
      {
        'name': 'done',
        'tasks': [
          {'id': 't4'},
        ],
      },
    ],
  }),
);

Future<void> _pumpWork(
  WidgetTester tester, {
  List<(String, HermesJob)> jobs = const [],
  List<Approval> approvals = const [],
  Future<List<HermesTeam>> Function()? teams,
  HermesKanbanSummary? kanban,
  double textScale = 1,
  Size size = const Size(412, 1400),
}) async {
  _opened.clear();
  _params.clear();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _router();
  addTearDown(router.dispose);
  NavigationService.attachRouter(router);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesBotsProvider.overrideWith((ref) async => _bots),
        hermesHomeProfileJobsProvider.overrideWith((ref) async => jobs),
        hermesKanbanSummaryProvider.overrideWith((ref) async => kanban),
        hermesTeamsProvider.overrideWith((ref) => (teams ?? () async => [])()),
        approvalsPendingProvider.overrideWith((ref) async => approvals),
        hermesHomePendingDecisionsProvider.overrideWith((ref) async => []),
        hermesAttentionPreparedProvider.overrideWith((ref) async => []),
        hermesAttentionFailedJobsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Approval _approval(String id) => Approval(
  id: id,
  actionType: 'send_email',
  description: 'Send it',
  status: ApprovalStatus.pending,
  createdAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  requestedBy: 'kai',
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });
  tearDown(PreferencesStore.debugReset);

  testWidgets('lists the team as compact rows, Chief by its name', (
    tester,
  ) async {
    await _pumpWork(tester);
    expect(find.text('Work'), findsWidgets);
    expect(find.text('TEAM · 2'), findsOneWidget);
    expect(find.text('Chief'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    expect(find.text('Kai'), findsOneWidget);
    expect(find.text('No recent activity'), findsNWidgets(2));
  });

  testWidgets('says one true thing about each place', (tester) async {
    await _pumpWork(
      tester,
      jobs: [
        ('kai', const HermesJob(id: 'a', prompt: 'p', schedule: '* * * * *')),
        (
          'kai',
          const HermesJob(
            id: 'b',
            prompt: 'p',
            schedule: '* * * * *',
            enabled: false,
          ),
        ),
      ],
      kanban: _board(),
      teams: () async => const [],
      approvals: [_approval('a1'), _approval('a2')],
    );
    expect(find.text('1 active · 2 total'), findsOneWidget);
    expect(find.text('4 tasks · 1 running · 1 done'), findsOneWidget);
    expect(find.text('Start a team'), findsOneWidget);
    expect(find.text('2 pending'), findsOneWidget);
    expect(find.text('Files Hermes made'), findsOneWidget);
    expect(find.text('Hermes settings'), findsOneWidget);
  });

  testWidgets('claims nothing it could not load', (tester) async {
    await _pumpWork(tester, teams: () async => throw StateError('no teams'));
    // Group Chat is optional: no Teams row without it.
    expect(find.text('Teams'), findsNothing);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Decide what agents may do'), findsOneWidget);
  });

  testWidgets('every row opens its route growing out of itself', (
    tester,
  ) async {
    final cases = <String, String>{
      'Scheduled agents': RouteNames.hermesJobs,
      'Kanban': RouteNames.hermesKanban,
      'Teams': RouteNames.hermesTeams,
      'Artifacts': RouteNames.hermesArtifacts,
      'Needs you': RouteNames.hermesAttention,
      'Approvals': RouteNames.hermesApprovals,
      'Hermes settings': RouteNames.hermesSettings,
    };
    for (final MapEntry(key: title, value: route) in cases.entries) {
      await _pumpWork(tester);
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(_opened.containsKey(route), isTrue, reason: title);
      expect(_opened[route], isA<HermezMorphOrigin>(), reason: title);
    }
  });

  testWidgets('a bot opens its page', (tester) async {
    await _pumpWork(tester);
    await tester.tap(find.text('Kai'));
    await tester.pumpAndSettle();
    expect(_params[RouteNames.hermesBotDetail], {'profile': 'kai'});
    expect(_opened[RouteNames.hermesBotDetail], isA<HermezMorphOrigin>());
  });

  testWidgets('offers notifications while they are off, and lets it go', (
    tester,
  ) async {
    await _pumpWork(tester);
    expect(find.text('Let your bots reach you'), findsOneWidget);
    await tester.tap(find.byTooltip('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Let your bots reach you'), findsNothing);
  });

  testWidgets('holds together at 320 px and 200% text', (tester) async {
    await _pumpWork(
      tester,
      kanban: _board(),
      textScale: 2,
      size: const Size(320, 820),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
