import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/motion/hermez_morph_origin.dart';
import 'package:conduit/features/hermes/motion/hermez_motion_surface.dart';
import 'package:conduit/features/hermes/providers/hermes_agentic_providers.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:conduit/features/hermes/views/hermes_attention_page.dart';
import 'package:conduit/features/hermes/views/hermes_home_page.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_composer.dart';
import 'package:conduit/features/hermes/widgets/hermes_home_presence.dart';
import 'package:conduit/features/hermes/widgets/hermes_tab_dock.dart';
import 'package:conduit/features/push/models/approval.dart';
import 'package:conduit/features/push/providers/push_providers.dart'
    show approvalsPendingProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Sessions extends HermesSessionsController {
  _Sessions(this.rows);
  final List<HermesSessionSummary> rows;

  @override
  Future<List<HermesSessionSummary>> build() async => rows;
}

class _FailingSessions extends HermesSessionsController {
  static var builds = 0;

  @override
  Future<List<HermesSessionSummary>> build() async {
    builds++;
    throw StateError('offline');
  }
}

class _Away extends HermesAwaySince {
  _Away(this.since);
  final DateTime since;

  @override
  DateTime? build() => since;
}

const _chief = HermesBot(
  name: 'default',
  title: 'Default',
  chatSessionId: 'chief-chat',
  preview: 'Asked Scout. PONG scout.',
);
const _kai = HermesBot(name: 'kai', title: 'Kai');

final _sessions = [
  const HermesSessionSummary(
    id: 'kai-1',
    title: 'Inventory migration',
    profile: 'kai',
    preview: 'Mapped 120 SKUs',
  ),
  const HermesSessionSummary(
    id: 'chief-chat',
    title: 'Bot Chat',
    profile: 'default',
    preview: 'Asked Scout. PONG scout.',
  ),
  const HermesSessionSummary(
    id: 'kai-2',
    title: 'Proposal review',
    profile: 'kai',
    preview: 'Two edits left',
  ),
];

HermesPendingDesktopDecision _decision(String request, {String? prompt}) =>
    HermesPendingDesktopDecision(
      origin: 'https://hermes.example',
      storedSessionId: 'kai-1',
      runtimeId: 'rt',
      requestId: request,
      kind: HermesPendingDesktopDecisionKind.clarification,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 20)),
      prompt: prompt,
      profile: 'kai',
    );

Approval _approval(String id) => Approval(
  id: id,
  actionType: 'send_email',
  description: 'Send the merchant follow-up',
  status: ApprovalStatus.pending,
  createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  requestedBy: 'kai',
  originProfile: 'kai',
);

/// Where each destination was opened from, by route name, and with what.
final _opened = <String, Object?>{};
final _openedParams = <String, Map<String, String>>{};

GoRouter _router({Widget home = const HermesHomePage()}) {
  GoRoute dest(String path, String name) => GoRoute(
    path: path,
    name: name,
    builder: (context, state) {
      _opened[name] = state.extra;
      _openedParams[name] = state.pathParameters;
      return Scaffold(body: Center(child: Text('dest:$name')));
    },
  );
  return GoRouter(
    initialLocation: Routes.hermesHome,
    routes: [
      GoRoute(path: Routes.hermesHome, builder: (context, state) => home),
      dest(Routes.hermesConversations, RouteNames.hermesConversations),
      dest(Routes.hermesAttention, RouteNames.hermesAttention),
      dest(Routes.hermesApproval, RouteNames.hermesApproval),
      dest(Routes.hermesJobs, RouteNames.hermesJobs),
    ],
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  List<HermesBot> bots = const [_chief, _kai],
  List<HermesSessionSummary>? sessions,
  HermesSessionsController Function()? sessionsController,
  List<HermesPendingDesktopDecision> decisions = const [],
  List<Approval> approvals = const [],
  List<HermesSessionSummary> prepared = const [],
  List<(String, HermesJob)> failed = const [],
  List<(String, HermesJob)> jobs = const [],
  Stream<List<HermesLiveSession>>? live,
  HermesDesktopApiService? service,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(412, 900),
  Widget home = const HermesHomePage(),
  List<Override> extra = const [],
}) async {
  _opened.clear();
  _openedParams.clear();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _router(home: home);
  addTearDown(router.dispose);
  NavigationService.attachRouter(router);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(service),
        hermesBotsProvider.overrideWith((ref) async => bots),
        hermesHomeProfileJobsProvider.overrideWith((ref) async => jobs),
        hermesSessionsProvider.overrideWith(
          sessionsController ?? () => _Sessions(sessions ?? _sessions),
        ),
        hermesHomePendingDecisionsProvider.overrideWith(
          (ref) async => decisions,
        ),
        approvalsPendingProvider.overrideWith((ref) async => approvals),
        hermesAttentionPreparedProvider.overrideWith((ref) async => prepared),
        hermesAttentionFailedJobsProvider.overrideWith((ref) async => failed),
        hermesActiveWorkProvider.overrideWith(
          (ref) => live ?? Stream.value(const <HermesLiveSession>[]),
        ),
        ...extra,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(brightness: brightness),
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

HermesDesktopApiService _desktopService() {
  final service = HermesDesktopApiService(
    config: const HermesConfig(
      enabled: true,
      baseUrl: 'https://hermes.example/v1',
      mode: HermesBackendMode.desktopGateway,
      desktopAuthKind: HermesDesktopAuthKind.nativePkce,
    ),
  );
  addTearDown(service.close);
  return service;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
    _FailingSessions.builds = 0;
  });
  tearDown(PreferencesStore.debugReset);

  group('header', () {
    testWidgets('is titled Conduit with no navigation button or tagline', (
      tester,
    ) async {
      await _pumpHome(tester);
      // The large title and, once it scrolls away, the compact one.
      expect(find.text('Conduit'), findsWidgets);
      expect(find.byTooltip('Navigation'), findsNothing);
      expect(find.textContaining('T H I N K I N G'), findsNothing);
      expect(find.byTooltip('New Hermes chat'), findsOneWidget);
    });

    testWidgets('shows nobody working while everything is idle', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHome(tester);
      expect(find.bySemanticsLabel(RegExp(' working: ')), findsNothing);
      handle.dispose();
    });

    testWidgets('shows who is working while Hermes reports it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpHome(
        tester,
        live: Stream.value([
          const HermesLiveSession(
            runtimeId: 'rt',
            storedId: 'kai-1',
            title: 'Inventory migration',
            status: 'working',
            preview: 'checking service logs',
          ),
        ]),
      );
      expect(
        find.bySemanticsLabel(RegExp('^1 agent working: kai')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('Needs you', () {
    testWidgets('is absent when nothing waits on the owner', (tester) async {
      await _pumpHome(tester);
      expect(find.textContaining('NEEDS YOU'), findsNothing);
      expect(find.textContaining('all clear'), findsNothing);
    });

    testWidgets('merges decisions and approvals under one counted heading', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        decisions: [_decision('r1', prompt: 'Which account should I use?')],
        approvals: [_approval('a1')],
      );
      expect(find.text('NEEDS YOU · 2'), findsOneWidget);
      expect(find.text('Which account should I use?'), findsOneWidget);
      expect(find.text('Kai · has a question'), findsOneWidget);
      expect(find.text('Send the merchant follow-up'), findsOneWidget);
      expect(find.text('Kai · approval'), findsOneWidget);
      // Few enough rows to need no See all.
      expect(find.text('See all'), findsNothing);
    });

    testWidgets('an approval opens its own detail; a failed run opens the '
        'schedule', (tester) async {
      await _pumpHome(
        tester,
        approvals: [_approval('a1')],
        failed: [
          (
            'ops',
            const HermesJob(
              id: 'j1',
              name: 'Nightly report',
              prompt: 'Report',
              schedule: '0 2 * * *',
              lastError: 'boom',
            ),
          ),
        ],
      );
      await tester.tap(find.text('Send the merchant follow-up'));
      await tester.pumpAndSettle();
      expect(_opened.containsKey(RouteNames.hermesApproval), isTrue);
      expect(_openedParams[RouteNames.hermesApproval], {'approvalId': 'a1'});
      expect(_opened[RouteNames.hermesApproval], isA<HermezMorphOrigin>());

      NavigationService.router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nightly report'));
      await tester.pumpAndSettle();
      expect(_opened.containsKey(RouteNames.hermesJobs), isTrue);
    });

    testWidgets('shows four rows and offers See all beyond that', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        decisions: [
          for (var i = 0; i < 6; i++) _decision('r$i', prompt: 'Question $i'),
        ],
      );
      expect(find.text('NEEDS YOU · 6'), findsOneWidget);
      expect(find.textContaining('Question '), findsNWidgets(4));
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(_opened[RouteNames.hermesAttention], isA<HermezMorphOrigin>());
    });
  });

  group('Conversations', () {
    testWidgets('pin Chief first and keep the rest newest first', (
      tester,
    ) async {
      await _pumpHome(tester);
      final chief = tester.getTopLeft(find.text('Chief'));
      final first = tester.getTopLeft(find.text('Inventory migration'));
      final second = tester.getTopLeft(find.text('Proposal review'));
      expect(chief.dy, lessThan(first.dy));
      expect(first.dy, lessThan(second.dy));
      expect(find.text('Asked Scout. PONG scout.'), findsOneWidget);
      expect(find.text('Mapped 120 SKUs'), findsOneWidget);
      // The pinned chat is not repeated under its stored title.
      expect(find.text('Bot Chat'), findsNothing);
    });

    testWidgets('replace the preview with the live line while an agent '
        'really works', (tester) async {
      await _pumpHome(
        tester,
        live: Stream.value([
          const HermesLiveSession(
            runtimeId: 'rt',
            storedId: 'kai-1',
            title: 'Inventory migration',
            status: 'working',
            preview: 'checking service logs…',
          ),
        ]),
      );
      expect(find.text('working · checking service logs…'), findsOneWidget);
      expect(find.text('Mapped 120 SKUs'), findsNothing);
      // Others keep their last words.
      expect(find.text('Two edits left'), findsOneWidget);
    });

    testWidgets('invite the owner to start with Chief when empty', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        sessions: const [],
        bots: const [HermesBot(name: 'default', title: 'Chief')],
      );
      expect(find.text('Start with Chief'), findsOneWidget);
    });

    testWidgets('All chats opens Conversations where there is no dock', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.tap(find.text('All chats'));
      await tester.pumpAndSettle();
      expect(_opened.containsKey(RouteNames.hermesConversations), isTrue);
    });

    testWidgets('All chats switches to the Chats tab under the dock', (
      tester,
    ) async {
      final selected = <int>[];
      await _pumpHome(
        tester,
        home: HermesDockScope(
          index: 0,
          select: selected.add,
          child: const HermesHomePage(),
        ),
      );
      await tester.tap(find.text('All chats'));
      await tester.pumpAndSettle();
      expect(selected, [1]);
      expect(_opened.containsKey(RouteNames.hermesConversations), isFalse);
    });

    testWidgets('leave delegated workers to their parent chat', (tester) async {
      await _pumpHome(
        tester,
        sessions: const [
          HermesSessionSummary(
            id: 'kai-1',
            title: 'Inventory migration',
            profile: 'kai',
          ),
          HermesSessionSummary(
            id: 'child',
            title: 'Worker: count SKUs',
            profile: 'kai',
            source: 'subagent',
          ),
        ],
      );
      expect(find.text('Inventory migration'), findsOneWidget);
      expect(find.text('Worker: count SKUs'), findsNothing);
    });
  });

  group('when Hermes cannot be reached', () {
    testWidgets('say so, offer Retry, and show no live state', (tester) async {
      await _pumpHome(
        tester,
        sessionsController: _FailingSessions.new,
        live: Stream.value([
          const HermesLiveSession(
            runtimeId: 'rt',
            storedId: 'kai-1',
            title: 'Inventory migration',
            status: 'working',
            preview: 'checking service logs…',
          ),
        ]),
      );
      expect(find.textContaining('Not connected'), findsOneWidget);
      expect(find.textContaining('Retry'), findsOneWidget);
      expect(find.textContaining('working ·'), findsNothing);

      final before = _FailingSessions.builds;
      await tester.tap(find.textContaining('Retry'));
      await tester.pumpAndSettle();
      expect(_FailingSessions.builds, greaterThan(before));
    });

    testWidgets('drop live state when the live feed fails', (tester) async {
      await _pumpHome(
        tester,
        live: Stream<List<HermesLiveSession>>.error(StateError('offline')),
      );
      expect(find.textContaining('Not connected'), findsOneWidget);
      expect(find.textContaining('working ·'), findsNothing);
    });

    testWidgets('are silent when everything answers', (tester) async {
      await _pumpHome(tester);
      expect(find.textContaining('Not connected'), findsNothing);
    });
  });

  group('Later today', () {
    testWidgets('is one muted line, only for routines still to run today', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(minutes: 1));
      if (soon.day != DateTime.now().day) return; // too close to midnight
      await _pumpHome(
        tester,
        jobs: [
          (
            'kai',
            HermesJob(
              id: 'j1',
              prompt: 'p',
              schedule: '* * * * *',
              nextRun: soon,
            ),
          ),
        ],
      );
      expect(find.text('Later today · 1 routine'), findsOneWidget);
      await tester.tap(find.text('Later today · 1 routine'));
      await tester.pumpAndSettle();
      expect(_opened[RouteNames.hermesJobs], isA<HermezMorphOrigin>());
    });

    testWidgets('is absent when none are due', (tester) async {
      await _pumpHome(tester);
      expect(find.textContaining('Later today'), findsNothing);
    });
  });

  group('While you were away', () {
    testWidgets('is one quiet line that opens its details in place', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        sessions: [
          HermesSessionSummary(
            id: 'kai-1',
            title: 'Inventory migration',
            profile: 'kai',
            updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ],
        extra: [
          hermesAwaySinceProvider.overrideWith(
            () => _Away(
              DateTime.now().toUtc().subtract(const Duration(hours: 2)),
            ),
          ),
        ],
      );
      expect(find.text('While you were away · 1 chat updated'), findsOneWidget);
      // Closed: the conversation shows once, in the inbox.
      expect(find.text('Inventory migration'), findsOneWidget);
      await tester.tap(find.textContaining('While you were away'));
      await tester.pumpAndSettle();
      expect(find.text('Inventory migration'), findsNWidgets(2));
      expect(find.text('Dismiss'), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('While you were away'), findsNothing);
    });

    testWidgets('is absent when nothing moved', (tester) async {
      await _pumpHome(
        tester,
        extra: [
          hermesAwaySinceProvider.overrideWith(
            () => _Away(
              DateTime.now().toUtc().subtract(const Duration(hours: 2)),
            ),
          ),
        ],
      );
      expect(find.textContaining('While you were away'), findsNothing);
    });
  });

  group('bottom of Home', () {
    // The dock is the one bottom element; Chief is the first conversation.
    testWidgets('has no second bar above the dock', (tester) async {
      await _pumpHome(tester, service: _desktopService());
      expect(find.byType(HermesHomeComposer), findsNothing);
    });
  });

  group('layout', () {
    testWidgets('every tappable row is at least 48 dp tall, rows 56', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        decisions: [_decision('r1', prompt: 'Which account?')],
        approvals: [_approval('a1')],
        extra: [
          hermesAwaySinceProvider.overrideWith(
            () => _Away(
              DateTime.now().toUtc().subtract(const Duration(hours: 2)),
            ),
          ),
        ],
      );
      final surfaces = find.byType(HermezMotionSurface);
      expect(surfaces, findsWidgets);
      for (final element in surfaces.evaluate()) {
        final height = element.size!.height;
        expect(height, greaterThanOrEqualTo(48), reason: '$element');
      }
      // The Needs you and conversation rows are full rows.
      for (final title in ['Which account?', 'Inventory migration']) {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(HermezMotionSurface),
        );
        expect(
          tester.getSize(row.first).height,
          greaterThanOrEqualTo(56),
          reason: title,
        );
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets('holds together at 320 px and 200% text in '
          '${brightness.name} mode with every section on', (tester) async {
        final soon = DateTime.now().add(const Duration(minutes: 1));
        await _pumpHome(
          tester,
          service: _desktopService(),
          brightness: brightness,
          textScale: 2,
          size: const Size(320, 820),
          decisions: [
            _decision(
              'r1',
              prompt:
                  'Which of the three merchant accounts should the follow-up '
                  'be sent from?',
            ),
          ],
          approvals: [_approval('a1')],
          jobs: [
            (
              'kai',
              HermesJob(
                id: 'j1',
                prompt: 'p',
                schedule: '* * * * *',
                nextRun: soon,
              ),
            ),
          ],
          live: Stream.value([
            const HermesLiveSession(
              runtimeId: 'rt',
              storedId: 'kai-1',
              title: 'Inventory migration',
              status: 'working',
              preview: 'checking the service logs for the last three deploys…',
            ),
          ]),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
