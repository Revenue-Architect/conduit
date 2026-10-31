import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_job.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/sheets/hermes_scheduled_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Routes extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  // The rule (m13): Scheduled is one card that puts what needs the owner
  // first, and "Schedule something" reshapes that card into New routine.
  testWidgets('Scheduled lists failures first and New routine is the same '
      'card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const jobs = <(String, HermesJob)>[
      (
        'kai',
        HermesJob(
          id: 'j1',
          name: 'Price watch',
          prompt: 'p',
          schedule: '0 9 * * 1',
          enabled: false,
        ),
      ),
      (
        'ops',
        HermesJob(
          id: 'j2',
          name: 'Push relay health',
          prompt: 'p',
          schedule: '0 * * * *',
        ),
      ),
      (
        'default',
        HermesJob(
          id: 'j3',
          name: 'Support drafts',
          prompt: 'p',
          schedule: '0 8 * * *',
          lastStatus: 'failed',
        ),
      ),
    ];
    final routes = _Routes();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesHomeProfileJobsProvider.overrideWith((ref) async => jobs),
          hermesBotsProvider.overrideWith((ref) async => const <HermesBot>[]),
        ],
        child: MaterialApp(
          navigatorObservers: [routes],
          home: const Scaffold(body: HermesScheduledCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final routesAtStart = routes.pushes;

    expect(find.text('1 on · 1 failed · 1 paused'), findsOneWidget);
    final top = [
      'Support drafts',
      'Push relay health',
      'Price watch',
    ].map((name) => tester.getTopLeft(find.text(name)).dy).toList();
    expect(top, orderedEquals([...top]..sort()));
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.text('Schedule something'));
    await tester.pumpAndSettle();
    expect(find.text('New routine'), findsOneWidget);
    expect(find.text('Save, paused'), findsOneWidget);
    expect(routes.pushes, routesAtStart);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule something'), findsOneWidget);
  });
}
