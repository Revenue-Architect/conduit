import 'dart:convert';

import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_page.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        expect(find.text('No private data.'), findsOneWidget);
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
    expect(find.text('Task title'), findsOneWidget);
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
        if (method == 'POST' && path.endsWith('/tasks')) {
          title = (jsonDecode(body!) as Map)['title'] as String;
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
    await tester.enterText(find.byType(TextField).last, 'QA sprint');
    await tester.tap(find.text('Save'));
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

    await tester.ensureVisible(find.text('Add comment'));
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Reviewed in QA');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'patch', 'comment']);
    expect(find.text('Reviewed in QA'), findsOneWidget);

    await tester.ensureVisible(find.text('Todo'));
    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(find.text('Move to Todo?'), findsOneWidget);
    expect(writes.length, 3);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(writes, ['create', 'patch', 'comment', 'patch']);
    expect(status, 'todo');
    expect(tester.takeException(), isNull);
  });
}
