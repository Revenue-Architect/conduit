import 'dart:convert';

import 'package:conduit/features/hermes/kanban/hermes_kanban_client.dart';
import 'package:conduit/features/hermes/kanban/hermes_kanban_page.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/shared/widgets/legacy_design_compatibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The app root is material_ui with a compatibility bridge; Hermes screens use
/// Flutter's material library. Opening a task must work under that root.
void main() {
  const config = HermesConfig(
    enabled: true,
    mode: HermesBackendMode.desktopGateway,
    baseUrl: 'https://example.test/v1',
    desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
  );

  testWidgets('a Kanban task opens under the real app root', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = HermesKanbanClient(
      config,
      request: (method, uri, {body}) async {
        if (uri.path.endsWith('/boards')) {
          return (
            status: 200,
            body: jsonEncode({
              'boards': [
                {'slug': 'synthetic', 'name': 'Synthetic projects', 'total': 1},
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
                  'name': 'done',
                  'tasks': [
                    {
                      'id': 't-1',
                      'title': 'Plan a fictional trip',
                      'status': 'done',
                      'priority': 0,
                      'assignee': 'example',
                      'comment_count': 2,
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
              'status': 'done',
              'body': 'No private data.',
              'priority': 0,
            },
            'comments': [],
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
          builder: (context, child) =>
              LegacyDesignCompatibility(child: child!),
          home: HermesKanbanPage(client: client),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Plan a fictional trip'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Actions'), findsOneWidget);
    await tester.tap(find.byTooltip('Close task details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
