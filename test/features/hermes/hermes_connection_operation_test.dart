import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/core/persistence/preferences_store.dart';
import 'package:conduit/features/hermes/models/hermes_config.dart';
import 'package:conduit/features/hermes/models/hermes_connection_operation.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:conduit/features/hermes/services/hermes_desktop_transport.dart';
import 'package:conduit/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _Socket extends Mock implements WebSocketChannel {}

final class _Sink extends Mock implements WebSocketSink {}

final class _Gateway {
  _Gateway() {
    when(() => socket.ready).thenAnswer((_) async {});
    when(() => socket.stream).thenAnswer((_) {
      scheduleMicrotask(ready);
      return incoming.stream;
    });
    when(() => socket.sink).thenReturn(sink);
    when(() => sink.close()).thenAnswer((_) async {});
    when(() => sink.add(any())).thenAnswer((invocation) {
      final frame = Map<String, dynamic>.from(
        jsonDecode(invocation.positionalArguments.single as String) as Map,
      );
      sent.add(frame);
      final id = frame['id'];
      if (id == null) return;
      final method = frame['method'] as String;
      scheduleMicrotask(
        () => incoming.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': switch (method) {
              'session.resume' => {
                'session_id': 'runtime-8',
                'stored_session_id': 'stored-8',
                'running': false,
                'info': {'running': false},
                'pending_connection': operationSnapshot,
              },
              'connection.respond' => {'status': 'ok', 'settled': false},
              'connectors.operation.wake' => {'status': 'ok'},
              _ => <String, Object?>{},
            },
          }),
        ),
      );
    });
  }

  final socket = _Socket();
  final sink = _Sink();
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];
  void ready() => incoming.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready', 'payload': {}},
    }),
  );
}

final class _Http implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(
      options.uri.path.endsWith('/messages')
          ? {'messages': <Object?>[]}
          : {
              'version': '0.21.5',
              'auth_required': false,
              'gateway_running': true,
            },
    ),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

final operationSnapshot = <String, Object?>{
  'op_id': 'operation-8',
  'seq': 1,
  'deadline_at':
      DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch /
      1000,
  'settled': false,
  'targets': [
    {
      'name': 'calendar',
      'kind': 'connector',
      'action': 'authorize',
      'state': 'pending',
      'connect_url': 'https://auth.example/connect?state=private',
    },
    {
      'name': 'mcp-weather',
      'kind': 'mcp',
      'action': 'install',
      'state': 'pending',
      'required_env': [
        {
          'name': 'WEATHER_TOKEN',
          'required': true,
          'secret': true,
          'default': 'do-not-persist',
          'prompt': 'API token',
        },
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PreferencesStore.debugReset);

  test(
    'request, update, pending snapshot and per-target RPC stay typed',
    () async {
      final request = HermesConnectionOperation.parse(operationSnapshot)!;
      expect(request.targets, hasLength(2));
      expect(request.targets.last.requiredEnv.single.secret, isTrue);

      final safe = request.safeJson();
      final safeText = jsonEncode(safe);
      expect(safeText, isNot(contains('auth.example')));
      expect(safeText, isNot(contains('do-not-persist')));
      final restored = HermesConnectionOperation.parse(safe, safeOnly: true)!;
      expect(restored.targets, hasLength(2));
      expect(restored.targets.last.requiredEnv.single.defaultValue, isNull);

      final update = HermesConnectionOperation.parse({
        ...operationSnapshot,
        'seq': 2,
        'settled': true,
        'targets': [
          (operationSnapshot['targets'] as List).first,
          {
            ...((operationSnapshot['targets'] as List).last as Map),
            'state': 'connected',
          },
        ],
      })!;
      expect(update.seq, 2);
      expect(update.settled, isTrue);
      expect(update.targets.last.state, HermesConnectionTargetState.connected);

      SharedPreferences.setMockInitialValues({});
      PreferencesStore.debugOverride(await SharedPreferences.getInstance());
      final gateway = _Gateway();
      final rpc = HermesDesktopRpcClient(
        channelFactory: (_, _, {httpClient}) => gateway.socket,
      );
      final dio = Dio()..httpClientAdapter = _Http();
      final service = HermesDesktopApiService(
        config: HermesConfig(
          enabled: true,
          baseUrl: 'https://hermes.example',
          mode: HermesBackendMode.desktopGateway,
          desktopProfile: 'research',
          desktopCredentials: HermesDesktopCredentials(
            legacyToken: 'test-token',
          ),
        ),
        dio: dio,
        rpc: rpc,
      );
      addTearDown(() async {
        service.close();
        await gateway.incoming.close();
      });

      await service.getSessionMessages('stored-8');
      expect(
        service.connectionOperationFor('runtime-8', 'operation-8')?.targets,
        hasLength(2),
      );
      await service.respondToConnectionOperation(
        runtimeId: 'runtime-8',
        storedSessionId: 'stored-8',
        operationId: 'operation-8',
        targets: const [
          {'name': 'calendar', 'status': 'approved'},
          {
            'name': 'mcp-weather',
            'status': 'approved',
            'env': {'WEATHER_TOKEN': 'entered-only-in-memory'},
          },
        ],
      );
      await service.wakeConnectorOperation(
        runtimeId: 'runtime-8',
        storedSessionId: 'stored-8',
        operationId: 'operation-8',
      );
      final respond = gateway.sent.singleWhere(
        (frame) => frame['method'] == 'connection.respond',
      );
      final params = respond['params'] as Map;
      expect(params['op_id'], 'operation-8');
      expect(params['owner'], {'type': 'session', 'session_id': 'runtime-8'});
      expect((params['result'] as Map)['targets'], hasLength(2));
      expect(params['profile'], 'research');
      expect(
        gateway.sent.any(
          (frame) => frame['method'] == 'connectors.operation.wake',
        ),
        isTrue,
      );
      void sendUpdate(int seq, {bool settled = false}) => gateway.incoming.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': 'connection.update',
            'session_id': 'runtime-8',
            'payload': {...operationSnapshot, 'seq': seq, 'settled': settled},
          },
        }),
      );
      sendUpdate(5);
      await Future<void>.delayed(Duration.zero);
      sendUpdate(4);
      await Future<void>.delayed(Duration.zero);
      final pending = await HermesPendingDecisionStore.forSession(
        origin: HermesConfig.connectionOrigin('https://hermes.example')!,
        storedSessionId: 'stored-8',
      );
      expect(
        service.connectionOperationFor('runtime-8', 'operation-8')?.seq,
        5,
      );
      expect(pending.single.connectionOperation?.seq, 5);
      sendUpdate(6, settled: true);
      await Future<void>.delayed(Duration.zero);
      sendUpdate(3);
      await Future<void>.delayed(Duration.zero);
      expect(
        await HermesPendingDecisionStore.forSession(
          origin: HermesConfig.connectionOrigin('https://hermes.example')!,
          storedSessionId: 'stored-8',
        ),
        isEmpty,
      );
    },
  );
}
