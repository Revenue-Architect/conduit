import 'dart:convert';

import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = HermesConfig(
    enabled: true,
    mode: HermesBackendMode.desktopGateway,
    baseUrl: 'https://example.test/hermes/v1',
  );

  test(
    'boards and eight installed lanes parse without private fixtures',
    () async {
      final calls = <Uri>[];
      final client = HermesKanbanClient(
        config,
        request: (method, uri, {body}) async {
          calls.add(uri);
          if (uri.path.endsWith('/boards')) {
            return (
              status: 200,
              body: jsonEncode({
                'boards': [
                  {'slug': 'test-board', 'name': 'Test Board', 'total': 2},
                ],
              }),
            );
          }
          return (
            status: 200,
            body: jsonEncode({
              'columns': [
                {
                  'name': 'todo',
                  'tasks': [
                    {
                      'id': 't-1',
                      'title': 'Plan a trip',
                      'status': 'todo',
                      'priority': 2,
                      'progress': {'done': 1, 'total': 3},
                    },
                  ],
                },
              ],
              'latest_event_id': 42,
            }),
          );
        },
      );
      final boards = await client.boards();
      final snapshot = await client.board('test-board');
      expect(boards.single.name, 'Test Board');
      expect(snapshot.lanes.length, 8);
      expect(snapshot.lanes['todo']!.single.childTotal, 3);
      expect(snapshot.lanes['running'], isEmpty);
      expect(snapshot.eventId, 42);
      expect(calls.last.queryParameters['board'], 'test-board');
      expect(calls.last.path, '/hermes/api/plugins/kanban/board');
    },
  );

  test(
    'every scoped write targets selected board, and running is refused',
    () async {
      final calls = <({String method, Uri uri, String? body})>[];
      final client = HermesKanbanClient(
        config,
        request: (method, uri, {body}) async {
          calls.add((method: method, uri: uri, body: body));
          return (status: 200, body: '{}');
        },
      );
      await client.create('project-x', 'Draft itinerary');
      await client.comment('project-x', 't/1', 'Reviewed');
      await client.patchTask('project-x', 't/1', {'priority': 4});
      expect(calls.length, 3);
      expect(
        calls.every((call) => call.uri.queryParameters['board'] == 'project-x'),
        isTrue,
      );
      expect(calls[1].uri.path, endsWith('/tasks/t%2F1/comments'));
      expect(jsonDecode(calls[2].body!)['priority'], 4);
      expect(
        () => client.patchTask('project-x', 't/1', {'status': 'running'}),
        throwsArgumentError,
      );
    },
  );

  test('auth and dependency conflicts are explicit', () async {
    final auth = HermesKanbanClient(
      config,
      request: (_, _, {body}) async => (status: 401, body: ''),
    );
    await expectLater(
      auth.boards(),
      throwsA(isA<KanbanApiException>().having((e) => e.status, 'status', 401)),
    );
    final conflict = HermesKanbanClient(
      config,
      request: (_, _, {body}) async =>
          (status: 409, body: '{"detail":"Parent task unfinished"}'),
    );
    await expectLater(
      conflict.patchTask('project-x', 't-1', {'status': 'ready'}),
      throwsA(
        isA<KanbanApiException>().having(
          (e) => e.message,
          'message',
          contains('Parent task'),
        ),
      ),
    );
  });

  test(
    'profiles are scoped to Hermes and task creation carries the assignee',
    () async {
      final calls = <({String method, Uri uri, String? body})>[];
      final client = HermesKanbanClient(
        config,
        request: (method, uri, {body}) async {
          calls.add((method: method, uri: uri, body: body));
          if (uri.path.endsWith('/profiles')) {
            return (
              status: 200,
              body: '{"profiles":[{"name":"kai","description":"General"},{"name":"invalid name"}]}',
            );
          }
          return (status: 200, body: '{}');
        },
      );
      expect((await client.profiles()).map((p) => p.name), ['kai']);
      await client.create('project-x', 'Write a summary', assignee: 'kai');
      expect(calls.first.uri.path, '/hermes/api/plugins/kanban/profiles');
      expect(calls.last.uri.queryParameters['board'], 'project-x');
      expect(jsonDecode(calls.last.body!)['assignee'], 'kai');
    },
  );

  test(
    'native PKCE uses existing bearer-capable request path, never cookies',
    () async {
      final calls = <({String method, String path, String? board})>[];
      final native = HermesKanbanClient(
        const HermesConfig(
          enabled: true,
          mode: HermesBackendMode.desktopGateway,
          desktopAuthKind: HermesDesktopAuthKind.nativePkce,
          baseUrl: 'https://example.test/hermes/v1',
        ),
        nativeRequest: (method, path, {board, body}) async {
          calls.add((method: method, path: path, board: board));
          if (path.endsWith('/boards')) {
            return {
              'boards': [
                {'slug': 'native', 'name': 'Native board'},
              ],
            };
          }
          if (path.endsWith('/profiles')) {
            return {
              'profiles': [
                {'name': 'kai', 'description': 'Native profile'},
              ],
            };
          }
          return {
            'columns': [
              {'name': 'todo', 'tasks': []},
            ],
          };
        },
      );
      expect((await native.boards()).single.name, 'Native board');
      expect((await native.board('native')).lanes['todo'], isEmpty);
      expect((await native.profiles()).single.name, 'kai');
      expect(calls[1].path, '/api/plugins/kanban/board');
      expect(calls[1].board, 'native');
      expect(calls.last.path, '/api/plugins/kanban/profiles');
      await native.close();
    },
  );
}
