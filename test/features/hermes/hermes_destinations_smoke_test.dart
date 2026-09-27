import 'package:conduit/features/hermes/kanban/hermes_kanban_summary_provider.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/views/hermes_attention_page.dart';
import 'package:conduit/features/hermes/views/hermes_bot_detail_page.dart';
import 'package:conduit/features/hermes/views/hermes_home_page.dart';
import 'package:conduit/features/hermes/views/hermes_live_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kai'), findsOneWidget);
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
      expect(find.text('STATUS'), findsOneWidget);
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
