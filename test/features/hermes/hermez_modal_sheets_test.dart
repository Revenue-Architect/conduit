import 'package:conduit/features/hermes/models/hermes_completed_run_snapshot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:conduit/features/hermes/sheets/hermes_attention_resolution_sheet.dart';
import 'package:conduit/features/hermes/sheets/hermes_completed_run_sheet.dart';
import 'package:conduit/features/hermes/sheets/hermes_scheduled_agent_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 412.0]) {
    testWidgets(
      'completed run sheet fits $width and returns conversation action',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        HermesCompletedRunAction? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      selected = await showHermesCompletedRunSheet(
                        context,
                        HermesCompletedRunSnapshot(
                          sessionId: 'session-1',
                          title: 'Synthetic research',
                          profile: 'kai',
                          completedAt: DateTime.utc(2026, 1, 1),
                          finalText: 'A concise real result.',
                          activity: const [],
                          artifacts: const [],
                        ),
                      );
                    },
                    child: const Text('Show'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pumpAndSettle();
        expect(find.text('Run complete'), findsOneWidget);
        expect(find.text('A concise real result.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Open conversation'));
        await tester.pumpAndSettle();
        expect(selected, HermesCompletedRunAction.conversation);
      },
    );
  }

  testWidgets('dismissing an approval sheet does not resolve it', (
    tester,
  ) async {
    final decision = HermesPendingDesktopDecision(
      origin: 'https://example.test',
      storedSessionId: 'stored-1',
      runtimeId: 'runtime-1',
      requestId: 'request-1',
      kind: HermesPendingDesktopDecisionKind.approval,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      prompt: 'Run a terminal command?',
    );
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result =
                    await showHermesAttentionResolutionSheet(context, decision),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Run a terminal command?'), findsOneWidget);
    expect(find.text('Approve once'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheduled agent sheet uses real job fields and fits 320 px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showHermesScheduledAgentSheet(
            context,
            profile: 'kai',
            job: const HermesJob(
              id: 'job-1',
              name: 'Research digest',
              prompt: 'Summarize the latest research.',
              schedule: '0 9 * * 1-5',
            ),
          ),
          child: const Text('Show'),
        ),
      )),
    )));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Research digest'), findsOneWidget);
    expect(find.text('Summarize the latest research.'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
