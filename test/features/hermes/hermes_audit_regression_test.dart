import 'package:conduit/core/models/conversation.dart';
import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/core/providers/app_providers.dart';
import 'package:conduit/features/chat/utils/streaming_reveal.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/views/hermes_jobs_page.dart';
import 'package:conduit/features/hermes/views/hermes_settings_sections.dart';
import 'package:conduit/features/hermes/widgets/hermes_session_tile.dart';
import 'package:conduit/features/hermes/widgets/hermes_sessions_tab.dart';
import 'package:conduit/features/navigation/providers/sidebar_search_providers.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:conduit/shared/widgets/legacy_design_compatibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Jobs extends HermesJobsController {
  @override
  Future<List<HermesJob>> build() async => const [
    HermesJob(
      id: 'healthy',
      name: 'Healthy job',
      prompt: '',
      schedule: 'every 1h',
    ),
    HermesJob(
      id: 'later',
      name: 'Later failure',
      prompt: '',
      schedule: 'every 1h',
    ),
  ];
  void fail() => state = const AsyncData([
    HermesJob(
      id: 'healthy',
      name: 'Healthy job',
      prompt: '',
      schedule: 'every 1h',
    ),
    HermesJob(
      id: 'later',
      name: 'Later failure',
      prompt: '',
      schedule: 'every 1h',
      lastStatus: 'failed',
    ),
  ]);
}

class _Sessions extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => const [
    HermesSessionSummary(
      id: 'human',
      title: 'API conversation',
      profile: 'kai',
      source: 'api_server',
    ),
    HermesSessionSummary(
      id: 'auto',
      title: 'Scheduled automation',
      profile: 'kai',
      source: 'cron',
    ),
  ];
}

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
  child: MaterialApp(
    builder: (context, child) => LegacyDesignCompatibility(child: child!),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferencesStore.debugOverride(await SharedPreferences.getInstance());
  });
  tearDown(PreferencesStore.debugReset);

  test('failure without diagnostic text and delivery-only failure count', () {
    for (final status in ['failed', 'error', 'TIMEOUT']) {
      expect(
        HermesJob(
          id: 'j',
          prompt: '',
          schedule: '',
          lastStatus: status,
        ).isFailing,
        isTrue,
      );
    }
    expect(
      const HermesJob(
        id: 'j',
        prompt: '',
        schedule: '',
        lastDeliveryError: 'Rejected',
      ).isFailing,
      isTrue,
    );
    expect(
      const HermesJob(
        id: 'j',
        prompt: '',
        schedule: '',
        lastStatus: 'ok',
      ).isFailing,
      isFalse,
    );
  });

  test('API conversations are not inferred to be automated', () {
    expect(
      const HermesSessionSummary(
        id: 's',
        title: '',
        source: 'api_server',
      ).isAutomated,
      isFalse,
    );
    expect(
      const HermesSessionSummary(
        id: 's',
        title: '',
        source: 'cron',
      ).isAutomated,
      isTrue,
    );
  });

  test('long and growing streaming bursts complete at the time budget', () {
    for (final text in ['word ' * 400, '你好🌱' * 1000]) {
      final end = streamingRevealEnd(
        text: text,
        shown: 1,
        startedAtLength: 1,
        elapsed: const Duration(milliseconds: 200),
      );
      expect(end, text.length);
      for (var ms = 0; ms < 200; ms += 17) {
        final prefix = streamingRevealEnd(
          text: text,
          shown: 1,
          startedAtLength: 1,
          elapsed: Duration(milliseconds: ms),
        );
        expect(prefix, inInclusiveRange(1, text.length));
        if (prefix < text.length) {
          expect(
            text.codeUnitAt(prefix - 1),
            isNot(inInclusiveRange(0xD800, 0xDBFF)),
          );
        }
      }
    }
  });

  testWidgets('a new status-only failure sorts first and opens its controls', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesJobsProvider.overrideWith(_Jobs.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, const HermesJobsPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hermes-job-run-later')), findsNothing);
    (container.read(hermesJobsProvider.notifier) as _Jobs).fail();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hermes-job-run-later')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Later failure')).dy,
      lessThan(tester.getTopLeft(find.text('Healthy job')).dy),
    );
    expect(find.text('Last run failed'), findsWidgets);
  });

  testWidgets('unknown health is neutral and nested details remain available', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        hermesServerStatusProvider.overrideWith(
          (ref) async => {
            'version': '0.21.5',
            'components': {
              'mail': {'status': 'degraded'},
            },
          },
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, const HermesServerStatusSection()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Status unavailable'), findsOneWidget);
    expect(find.textContaining('Healthy'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('degraded'), findsOneWidget);
  });

  testWidgets('the selected compact conversation has a visible surface', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [hermesApiServiceProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    final now = DateTime(2026);
    container
        .read(activeConversationProvider.notifier)
        .set(
          Conversation(
            id: 'local:hermes_human',
            title: 'Human',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pumpWidget(
      _app(
        container,
        const HermesSessionTile(
          session: HermesSessionSummary(id: 'human', title: 'Human'),
          compact: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final materials = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(HermesSessionTile),
        matching: find.byType(Material),
      ),
    );
    expect(
      materials.any((m) => m.color != null && m.color != Colors.transparent),
      isTrue,
    );
  });

  testWidgets('bot search highlights matches and includes API chats', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesSessionsProvider.overrideWith(_Sessions.new),
        hermesBotsProvider.overrideWith(
          (ref) async => const [HermesBot(name: 'kai', title: 'Kai Assistant')],
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(sidebarSearchFieldControllerProvider).text = 'Kai';
    await tester.pumpWidget(_app(container, const HermesSessionsTab()));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Kai Assistant'));
    expect(
      (text.textSpan as TextSpan).children?.any(
        (span) =>
            span is TextSpan && span.text == 'Kai' && span.style?.color != null,
      ),
      isTrue,
    );
    container.read(sidebarSearchFieldControllerProvider).text =
        'API conversation';
    await tester.pumpAndSettle();
    expect(find.text('API conversation'), findsOneWidget);
  });
}
