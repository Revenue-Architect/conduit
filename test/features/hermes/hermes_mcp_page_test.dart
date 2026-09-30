import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:conduit/features/hermes/providers/hermes_providers.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/sheets/hermez_modal_sheet.dart';
import 'package:conduit/features/hermes/views/hermes_mcp_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

final class _MockWebSocketSink extends Mock implements WebSocketSink {}

/// A gateway that answers `mcp.*` and records every method it is asked for.
final class _McpGateway {
  _McpGateway() {
    when(() => channel.ready).thenAnswer((_) async {});
    when(() => channel.stream).thenAnswer((_) {
      scheduleMicrotask(_ready);
      return incoming.stream;
    });
    when(() => channel.sink).thenReturn(sink);
    when(() => sink.close()).thenAnswer((_) async {});
    when(() => sink.add(any())).thenAnswer((invocation) {
      final frame = Map<String, dynamic>.from(
        jsonDecode(invocation.positionalArguments.single as String) as Map,
      );
      final id = frame['id'];
      if (id == null) return;
      final method = frame['method']?.toString() ?? '';
      methods.add(method);
      final result = switch (method) {
        'mcp.servers.list' => {
          'servers': [
            {
              'name': 'github',
              'description': 'GitHub tools',
              'enabled': true,
              'tools': ['issues'],
            },
          ],
        },
        _ => <String, Object?>{},
      };
      scheduleMicrotask(
        () => incoming.add(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
        ),
      );
    });
  }

  final channel = _MockWebSocketChannel();
  final sink = _MockWebSocketSink();
  final incoming = StreamController<dynamic>.broadcast();
  final methods = <String>[];

  void _ready() {
    if (incoming.isClosed) return;
    incoming.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}},
      }),
    );
  }

  Future<void> dispose() => incoming.close();
}

final class _StatusAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'version': '2026.9.14',
      'auth_required': false,
      'gateway_running': true,
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// The writes the page sent (list reads excluded).
List<String> _writes(_McpGateway gateway) => gateway.methods
    .where(
      (method) => method.startsWith('mcp.') && method != 'mcp.servers.list',
    )
    .toList();

Future<_McpGateway> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final gateway = _McpGateway();
  final service = HermesDesktopApiService(
    config: HermesConfig(
      enabled: true,
      baseUrl: 'https://hermes.example',
      mode: HermesBackendMode.desktopGateway,
      desktopCredentials: HermesDesktopCredentials(
        legacyToken: 'session-token',
      ),
    ),
    dio: Dio()..httpClientAdapter = _StatusAdapter(),
    rpc: HermesDesktopRpcClient(
      channelFactory: (_, _, {httpClient}) => gateway.channel,
    ),
  );
  addTearDown(() async {
    service.close();
    await gateway.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [hermesApiServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: HermesMcpPage()),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return gateway;
}

void main() {
  testWidgets('server actions open in a tray under the row, not a popup', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Test'), findsNothing);
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    for (final action in [
      'Test',
      'Authenticate',
      'Set API key',
      'Disable tools',
      'Remove',
    ]) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
  });

  testWidgets('Remove is guarded in the tray; Cancel sends nothing; Remove '
      'sends once', (tester) async {
    final gateway = await _pump(tester);
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('REMOVE GITHUB?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('REMOVE GITHUB?'), findsNothing);
    expect(_writes(gateway), isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(_writes(gateway), ['mcp.servers.remove']);
  });

  testWidgets('Set API key grows a secure sheet from the server row', (
    tester,
  ) async {
    final gateway = await _pump(tester);
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set API key'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(HermezModalSheet),
        matching: find.byType(TextField),
      ),
    );
    expect(field.obscureText, isTrue);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);

    await tester.enterText(find.byType(TextField).last, 'sk-test');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_writes(gateway), ['mcp.servers.set_api_key']);
  });

  testWidgets('Add MCP server opens the editor sheet; Cancel adds nothing', (
    tester,
  ) async {
    final gateway = await _pump(tester);
    await tester.tap(find.byTooltip('Add MCP server'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsOneWidget);
    for (final label in [
      'Name',
      'HTTP URL',
      'stdio command',
      'Arguments (one per line)',
      'API key (optional)',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(HermezModalSheet), findsNothing);
    expect(_writes(gateway), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
