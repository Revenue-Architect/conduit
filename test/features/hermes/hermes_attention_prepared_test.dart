import 'package:conduit/features/hermes/kanban/hermes_kanban_summary_provider.dart';
import 'package:conduit/features/hermes/models/hermes_session.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/views/hermes_attention_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptySessionsController extends HermesSessionsController {
  @override
  Future<List<HermesSessionSummary>> build() async => [];
}

Future<void> _pump(
  WidgetTester tester,
  Future<List<HermesSessionSummary>> Function() prepared,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermesApiServiceProvider.overrideWithValue(null),
        hermesBotsProvider.overrideWith((ref) async => []),
        hermesKanbanSummaryProvider.overrideWith((ref) async => null),
        hermesSessionsProvider.overrideWith(_EmptySessionsController.new),
        hermesAttentionDecisionsProvider.overrideWith((ref) async => []),
        hermesAttentionFailedJobsProvider.overrideWith((ref) async => []),
        hermesAttentionPreparedProvider.overrideWith((ref) => prepared()),
      ],
      child: const MaterialApp(home: HermesAttentionPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failed prepared-work request is not shown as an all-clear', (
    tester,
  ) async {
    await _pump(tester, () async => throw StateError('offline'));
    expect(
      find.text('Some attention sources are unavailable. Pull to retry.'),
      findsOneWidget,
    );
    expect(find.text('Nothing needs your attention right now.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all sources empty shows the all-clear', (tester) async {
    await _pump(tester, () async => []);
    expect(find.text('Nothing needs your attention right now.'), findsOneWidget);
    expect(
      find.text('Some attention sources are unavailable. Pull to retry.'),
      findsNothing,
    );
  });

  testWidgets('prepared objective chats are listed for review', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => const [
        HermesSessionSummary(
          id: 'initiative-0123456789abcdef01234567',
          title: 'Forks field map ready',
          source: 'initiative_objective',
        ),
      ],
    );
    expect(find.text('Prepared for you'), findsOneWidget);
    expect(find.text('Forks field map ready'), findsOneWidget);
    expect(find.text('Nothing needs your attention right now.'), findsNothing);
  });
}
