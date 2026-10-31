import 'dart:convert';

import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_page.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Routes extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  // The rule (owner: Kanban is a card): Kanban opens as one card, grouped by
  // what it asks of the owner, and a task opens in that same card, never a
  // second card or a page.
  testWidgets('Kanban is one card; a task becomes the same card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = HermesKanbanClient(
      const HermesConfig(
        enabled: true,
        mode: HermesBackendMode.desktopGateway,
        baseUrl: 'https://example.test/v1',
        desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
      ),
      request: (_, uri, {body}) async {
        if (uri.path.endsWith('/boards')) {
          return (
            status: 200,
            body: '{"boards":[{"slug":"default","name":"Default"}]}',
          );
        }
        if (uri.path.contains('/tasks/')) {
          return (
            status: 200,
            body: jsonEncode({
              'task': {
                'id': 't-1',
                'title': 'Publish the holiday theme',
                'status': 'review',
                'assignee': 'kai',
              },
              'comments': [],
              'runs': [],
              'events': [],
              'links': {'parents': []},
              'attachments': [],
              'child_results': [],
            }),
          );
        }
        return (
          status: 200,
          body: jsonEncode({
            'columns': [
              {
                'name': 'review',
                'tasks': [
                  {
                    'id': 't-1',
                    'title': 'Publish the holiday theme',
                    'status': 'review',
                    'assignee': 'kai',
                  },
                ],
              },
              {
                'name': 'ready',
                'tasks': [
                  {'id': 't-2', 'title': 'Draft the FAQ', 'status': 'ready'},
                ],
              },
            ],
          }),
        );
      },
    );
    final routes = _Routes();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesBotsProvider.overrideWith((ref) async => const <HermesBot>[]),
        ],
        child: MaterialApp(
          navigatorObservers: [routes],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHermesKanbanCard(context, client: client),
                child: const Text('Kanban link'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kanban link'));
    await tester.pumpAndSettle();
    final routesWithCard = routes.pushes;

    expect(find.text('Needs you 1'), findsOneWidget);
    expect(find.text('Up next 1'), findsOneWidget);
    expect(find.text('Publish the holiday theme'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Needs you 1'), findsNothing);
    expect(routes.pushes, routesWithCard);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Needs you 1'), findsOneWidget);
    expect(routes.pushes, routesWithCard);
  });
}
