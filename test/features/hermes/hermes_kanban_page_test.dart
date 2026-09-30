import 'dart:convert';

import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_page.dart';
import 'package:conduit/features/hermes/views/hermes_artifacts_page.dart';
import 'package:conduit/core/services/navigation_service.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_bot.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('Kanban attachment identity requires a real server ID and filename', () {
    final target = HermesKanbanArtifactTarget.fromAttachment(
      board: 'default',
      taskId: 't-one',
      attachment: {'id': 19, 'filename': 'Plan.pdf'},
    );
    expect(target?.attachmentId, 19);
    expect(target?.filename, 'Plan.pdf');
    expect(
      HermesKanbanArtifactTarget.fromAttachment(
        board: 'default',
        taskId: 't-one',
        attachment: {'filename': 'Plan.pdf'},
      ),
      isNull,
    );
    expect(
      HermesKanbanArtifactTarget.fromAttachment(
        board: 'default',
        taskId: 't-one',
        attachment: {'id': 19, 'filename': '../secret'},
      ),
      isNull,
    );
  });

  testWidgets('task attachment opens its exact target in Artifacts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 950));
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
        if (uri.path.endsWith('/board')) {
          return (
            status: 200,
            body: jsonEncode({
              'columns': [
                {
                  'name': 'todo',
                  'tasks': [
                    {'id': 't-one', 'title': 'Linked task', 'status': 'todo'},
                  ],
                },
              ],
            }),
          );
        }
        if (uri.path.endsWith('/tasks/t-parent')) {
          return (
            status: 200,
            body: jsonEncode({
              'task': {
                'id': 't-parent',
                'title': 'Parent task view',
                'status': 'todo',
              },
              'comments': [],
              'runs': [],
              'events': [],
              'links': {
                'parents': [],
                'children': ['t-one'],
              },
              'attachments': [],
              'child_results': [],
            }),
          );
        }
        return (
          status: 200,
          body: jsonEncode({
            'task': {'id': 't-one', 'title': 'Linked task', 'status': 'todo'},
            'comments': [],
            'runs': [],
            'events': [],
            'links': {
              'parents': ['t-parent'],
              'children': [],
            },
            'attachments': [
              {
                'id': 19,
                'filename': 'Plan.pdf',
                'stored_path': '/private/attachment/Plan.pdf',
              },
            ],
            'child_results': [],
          }),
        );
      },
    );
    HermesKanbanArtifactTarget? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => HermesKanbanPage(client: client),
        ),
        GoRoute(
          path: Routes.hermesArtifacts,
          name: RouteNames.hermesArtifacts,
          builder: (_, state) {
            opened = state.extra as HermesKanbanArtifactTarget?;
            return const Scaffold(body: Text('Artifact destination'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Linked task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Linked items live in physical compartments that open in place.
    expect(find.text('Plan.pdf'), findsNothing);
    await tester.ensureVisible(find.textContaining('FILES /'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('FILES /'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Plan.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Artifact destination'), findsOneWidget);
    expect(opened?.board, 'default');
    expect(opened?.taskId, 't-one');
    expect(opened?.attachmentId, 19);
    expect(opened?.filename, 'Plan.pdf');
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linked task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.textContaining('DEPENDENCIES /'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('DEPENDENCIES /'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Parent task · t-parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parent task · t-parent'));
    await tester.pumpAndSettle();
    expect(find.text('Parent task view'), findsWidgets);
  });

  const config = HermesConfig(
    enabled: true,
    mode: HermesBackendMode.desktopGateway,
    baseUrl: 'https://example.test/v1',
    desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
  );

  for (final width in <double>[320, 360, 412]) {
    for (final brightness in Brightness.values) {
      testWidgets('Kanban task/detail at $width dp and $brightness', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final client = HermesKanbanClient(
          config,
          request: (method, uri, {body}) async {
            if (uri.path.endsWith('/boards')) {
              return (
                status: 200,
                body: jsonEncode({
                  'boards': [
                    {
                      'slug': 'synthetic',
                      'name': 'Synthetic projects',
                      'total': 1,
                    },
                  ],
                }),
              );
            }
            if (uri.path.endsWith('/board')) {
              return (
                status: 200,
                body: jsonEncode({
                  'columns': [
                    {
                      'name': 'todo',
                      'tasks': [
                        {
                          'id': 't-1',
                          'title': 'Plan a fictional trip',
                          'status': 'todo',
                          'priority': 2,
                          'assignee': 'example',
                          'comment_count': 1,
                          'progress': {'done': 1, 'total': 2},
                        },
                      ],
                    },
                  ],
                }),
              );
            }
            return (
              status: 200,
              body: jsonEncode({
                'task': {
                  'id': 't-1',
                  'title': 'Plan a fictional trip',
                  'status': 'todo',
                  'body': 'No private data.',
                  'priority': 2,
                },
                'comments': [
                  {'body': 'Check the route', 'author': 'tester'},
                ],
                'runs': [],
                'events': [],
                'links': {'parents': []},
                'attachments': [],
                'child_results': [],
              }),
            );
          },
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(2),
                ),
                child: HermesKanbanPage(client: client),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Synthetic projects'), findsOneWidget);
        expect(find.text('Plan a fictional trip'), findsOneWidget);
        await tester.tap(find.text('Plan a fictional trip'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Actions'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('No private data.'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('No private data.'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Live activity'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Live activity'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Check the route'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Check the route'), findsOneWidget);
      });
    }
  }

  testWidgets('new-task dialog closes and Kanban route tears down safely', (
    tester,
  ) async {
    final client = HermesKanbanClient(
      config,
      request: (_, uri, {body}) async {
        if (uri.path.endsWith('/boards')) {
          return (
            status: 200,
            body: '{"boards":[{"slug":"default","name":"Default"}]}',
          );
        }
        return (status: 200, body: '{"columns":[]}');
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HermesKanbanPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    expect(find.text('Title *'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('create, edit, comment, and confirm a move refresh from Hermes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? title;
    var status = 'ready';
    final comments = <String>[];
    final writes = <String>[];
    final client = HermesKanbanClient(
      config,
      request: (method, uri, {body}) async {
        final path = uri.path;
        if (path.endsWith('/boards')) {
          return (
            status: 200,
            body: '{"boards":[{"slug":"qa","name":"QA board"}]}',
          );
        }
        if (path.endsWith('/profiles')) {
          return (
            status: 200,
            body: '{"profiles":[{"name":"kai","description":"General agent"}]}',
          );
        }
        if (method == 'POST' && path.endsWith('/tasks')) {
          final payload = jsonDecode(body!) as Map;
          title = payload['title'] as String;
          expect(payload['assignee'], 'kai');
          expect(payload['body'], 'Research the route');
          expect(payload['priority'], 0);
          status = payload['triage'] == true ? 'triage' : 'ready';
          writes.add('create');
          return (status: 200, body: '{}');
        }
        if (method == 'PATCH') {
          final patch = jsonDecode(body!) as Map;
          if (patch['title'] is String) title = patch['title'] as String;
          if (patch['status'] is String) status = patch['status'] as String;
          writes.add('patch');
          return (status: 200, body: '{}');
        }
        if (method == 'POST' && path.endsWith('/comments')) {
          comments.add((jsonDecode(body!) as Map)['body'] as String);
          writes.add('comment');
          return (status: 200, body: '{}');
        }
        final task = {
          'id': 't-qa',
          'title': title ?? '',
          'status': status,
          'priority': 1,
        };
        if (path.endsWith('/board')) {
          return (
            status: 200,
            body: jsonEncode({
              'columns': [
                {
                  'name': 'todo',
                  'tasks': title != null && status == 'todo' ? [task] : [],
                },
                {
                  'name': 'ready',
                  'tasks': title != null && status == 'ready' ? [task] : [],
                },
              ],
            }),
          );
        }
        return (
          status: 200,
          body: jsonEncode({
            'task': task,
            'comments': [
              for (final text in comments) {'body': text, 'author': 'qa'},
            ],
            'runs': [],
            'events': [],
            'links': {'parents': []},
            'attachments': [],
            'child_results': [],
          }),
        );
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HermesKanbanPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'QA sprint');
    await tester.enterText(find.byType(TextField).last, 'Research the route');
    // Status, bot and priority live in the OPTIONS compartment.
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ready').last);
    await tester.tap(find.text('Assign a bot (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create task'));
    await tester.pumpAndSettle();
    expect(writes, ['create']);
    expect(find.text('QA sprint'), findsOneWidget);

    await tester.tap(find.text('QA sprint'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Updated QA sprint');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'patch']);
    expect(find.text('Updated QA sprint'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Add comment'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
    // The comment field opens in place under its button.
    await tester.enterText(find.byType(TextField).last, 'Reviewed in QA');
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'patch', 'comment']);
    await tester.scrollUntilVisible(
      find.text('Live activity'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Live activity'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reviewed in QA'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Reviewed in QA'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(ActionChip, 'Todo'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(ActionChip, 'Todo'));
    await tester.pumpAndSettle();
    // The move is held open in a guard under the status controls.
    expect(find.text('MOVE TO TODO?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(writes.length, 3);
    // Keep current closes the guard and changes nothing.
    await tester.ensureVisible(find.text('Keep current'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep current'));
    await tester.pumpAndSettle();
    expect(find.text('MOVE TO TODO?'), findsNothing);
    expect(writes.length, 3);
    // Running is never offered as a manual move.
    expect(find.widgetWithText(ActionChip, 'Running'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, 'Todo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Move'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'patch', 'comment', 'patch']);
    expect(status, 'todo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('assignee offers installed Hermes profiles', (tester) async {
    final client = HermesKanbanClient(
      config,
      request: (method, uri, {body}) async {
        if (uri.path.endsWith('/profiles')) {
          return (
            status: 200,
            body: '{"profiles":[{"name":"kai","description":"General"},{"name":"autopilot","description":"Background work"}]}',
          );
        }
        if (uri.path.endsWith('/boards')) {
          return (status: 200, body: '{"boards":[{"slug":"qa","name":"QA"}]}');
        }
        if (uri.path.endsWith('/board')) {
          return (
            status: 200,
            body: '{"columns":[{"name":"ready","tasks":[{"id":"t-1","title":"A task","status":"ready"}]}]}',
          );
        }
        return (
          status: 200,
          body: '{"task":{"id":"t-1","title":"A task","status":"ready"},"comments":[],"runs":[],"events":[],"links":{},"attachments":[],"child_results":[]}',
        );
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HermesKanbanPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('A task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assignee'));
    await tester.pumpAndSettle();
    expect(find.text('autopilot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task form uses the Bot Mode roster and neutral sheet surface', (
    tester,
  ) async {
    var pluginRosterCalled = false;
    final client = HermesKanbanClient(
      config,
      request: (_, uri, {body}) async {
        if (uri.path.endsWith('/boards')) {
          return (status: 200, body: '{"boards":[{"slug":"qa","name":"QA"}]}');
        }
        if (uri.path.endsWith('/profiles')) {
          pluginRosterCalled = true;
          return (status: 200, body: '{"profiles":[]}');
        }
        return (status: 200, body: '{"columns":[]}');
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesBotsProvider.overrideWith(
            (ref) async => const [
              HermesBot(name: 'kai', title: 'Kai', description: 'Research'),
              HermesBot(name: 'strong', title: 'Strong'),
            ],
          ),
        ],
        child: MaterialApp(home: HermesKanbanPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('New task').last))
          .dialogTheme
          .backgroundColor,
      const Color(0xFFFFFFFF),
    );
    await tester.tap(find.text('OPTIONS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign a bot (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('kai'), findsOneWidget);
    expect(find.text('strong'), findsOneWidget);
    expect(pluginRosterCalled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board refreshes agent status while visible', (tester) async {
    var status = 'ready';
    final client = HermesKanbanClient(
      config,
      request: (method, uri, {body}) async {
        if (uri.path.endsWith('/boards')) {
          return (status: 200, body: '{"boards":[{"slug":"qa","name":"QA"}]}');
        }
        return (
          status: 200,
          body: jsonEncode({
            'columns': [
              {
                'name': status,
                'tasks': [
                  {'id': 't-1', 'title': 'Agent work', 'status': status},
                ],
              },
            ],
          }),
        );
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: HermesKanbanPage(client: client)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    status = 'running';
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
